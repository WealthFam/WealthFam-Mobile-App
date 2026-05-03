import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telephony/telephony.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(SyncTaskHandler());
}

@pragma('vm:entry-point')
class SyncTaskHandler extends TaskHandler {
  int _eventCount = 0;
  Timer? _timer;
  bool _isProcessingQueue = false;
  bool _isProcessingOfflineQueue = false;
  String? _resolvedFilesPath;

  @override
  @pragma('vm:entry-point')
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    try {
      final Directory appDir = await getApplicationSupportDirectory();
      _resolvedFilesPath = appDir.parent.path;
    } catch (e) {
      _resolvedFilesPath = '/data/user/0/com.wealthfam.mobile_app';
    }

    // Perform a one-time catch-up scan of the last 24h quietly in the background
    _performCatchUpScan();

    // Start reliable 5s timer for native queue check
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _eventCount++;
      _checkNativeSmsQueue();

      // Every 20 seconds (4 ticks): Retry offline queue
      if (_eventCount % 4 == 0) {
        _retryOfflineQueue();
      }

      if (_eventCount % 12 == 0) {
        // Every minute
        _updateNotificationAsync();
      }
    });

    await _checkNativeSmsQueue();
    _updateNotificationAsync();
  }

  Future<void> _retryOfflineQueue() async {
    if (_isProcessingOfflineQueue) return;
    _isProcessingOfflineQueue = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final List<String> queue = prefs.getStringList('sms_offline_queue') ?? [];
      if (queue.isEmpty) {
        _isProcessingOfflineQueue = false;
        return;
      }

      final List<String> remaining = [];
      bool stopDueToFailure = false;
      int processedCount = 0;

      // Process batch of max 10 to avoid blocking isolate too long
      for (final itemStr in queue) {
        if (stopDueToFailure || processedCount >= 10) {
          remaining.add(itemStr);
          continue;
        }

        try {
          final data = jsonDecode(itemStr) as Map<String, dynamic>;
          // Use isRetry=true to ensure only 1 attempt per item in this cycle
          final success = await _handleNativeSms(data, isRetry: true);
          
          if (success) {
            processedCount++;
          } else {
            // Fail-fast: If one fails, network is likely down. Stop trying the rest.
            remaining.add(itemStr);
            stopDueToFailure = true;
          }
        } catch (_) {
          remaining.add(itemStr);
          stopDueToFailure = true;
        }
      }

      if (processedCount > 0) {
        // Reload again to ensure we don't overwrite items added by other isolates/threads
        await prefs.reload();
        final currentQueue = prefs.getStringList('sms_offline_queue') ?? [];
        
        // Match by hash to remove only the ones we successfully processed
        // This is safer than just saving 'remaining' in case new items were added
        // But for simplicity and since we are in a 5s tick, we can just filter
        // Wait, the safest way is to filter currentQueue by removing what we synced
        // But since we don't have the hashes here easily, we'll use the 'remaining' logic
        // and just append anything that was added to currentQueue while we were working.
        
        // Actually, the 'remaining' list contains everything we didn't process.
        // If currentQueue has more items than our original 'queue', it means new items arrived.
        if (currentQueue.length > queue.length) {
          final newItems = currentQueue.sublist(queue.length);
          remaining.addAll(newItems);
        }
        
        await prefs.setStringList('sms_offline_queue', remaining);
      }
    } finally {
      _isProcessingOfflineQueue = false;
    }
  }

  Future<void> _performCatchUpScan() async {
    try {
      final Telephony telephony = Telephony.instance;
      final cutoff = DateTime.now()
          .subtract(const Duration(hours: 24))
          .millisecondsSinceEpoch;

      final messages = await telephony.getInboxSms(
        columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
        filter: SmsFilter.where(
          SmsColumn.DATE,
        ).greaterThanOrEqualTo(cutoff.toString()),
      );

      if (messages.isEmpty) {
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      // Fetch location ONCE for the entire batch to save battery/time
      double? batchLat;
      double? batchLng;
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
          ),
        ).timeout(const Duration(seconds: 10));
        batchLat = pos.latitude;
        batchLng = pos.longitude;
      } catch (_) {}

      for (final msg in messages) {
        if (msg.address == null || msg.body == null || msg.date == null) {
          continue;
        }

        // Use same hashing logic
        final dateStr = msg.date.toString();
        String cleanDate = dateStr;
        try {
          final ms = int.tryParse(dateStr) ?? double.parse(dateStr).toInt();
          final dt = DateTime.fromMillisecondsSinceEpoch(ms);
          cleanDate =
              "${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}${dt.hour.toString().padLeft(2, '0')}";
        } catch (_) {}

        final cleanSender = msg.address!.toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9]'),
          '',
        );
        final cleanMessage = msg.body!.toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9]'),
          '',
        );
        final raw = '$cleanSender-$cleanDate-$cleanMessage';
        final hash = sha256.convert(utf8.encode(raw)).toString();

        if (!prefs.containsKey('sms_hash_$hash')) {
          await _handleNativeSms({
            'sender': msg.address,
            'message': msg.body,
            'date': msg.date,
            'latitude': batchLat,
            'longitude': batchLng,
          }, isRetry: true);
        }
      }
    } catch (e) {
      // Catch-up scan failed, ignoring for now
    }
  }

  @override
  @pragma('vm:entry-point')
  void onRepeatEvent(DateTime timestamp) {
    // Plugin's built-in heartbeat is redundant now that we have a reliable Timer.periodic.
    // We keep the log for diagnostics but delegate all processing to the 5s Timer.
    _updateNotificationAsync();
  }

  Future<void> _checkNativeSmsQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;
    try {
      final rootPath =
          _resolvedFilesPath ?? '/data/user/0/com.wealthfam.mobile_app';
      final directory = Directory('$rootPath/files/sms_relay');

      if (!await directory.exists()) {
        _isProcessingQueue = false;
        return;
      }

      final List<FileSystemEntity> files = await directory.list().toList();
      if (files.isEmpty) {
        _isProcessingQueue = false;
        return;
      }

      for (var file in files) {
        if (file is File && file.path.endsWith('.json')) {
          try {
            final String content = await file.readAsString();
            final data = jsonDecode(content) as Map<String, dynamic>;

            final success = await _handleNativeSms(data);
            if (success) {
              if (await file.exists()) {
                await file.delete();
              }
            }
          } catch (e) {
            if (await file.exists()) {
              await file.delete();
            }
          }
        }
      }

      _isProcessingQueue = false;
    } catch (e) {
      // Directory listing or general processing failed
      _isProcessingQueue = false;
    }
  }

  @override
  @pragma('vm:entry-point')
  void onReceiveData(Object data) {
    if (data is Map<String, dynamic> && data['type'] == 'sms') {
      _handleNativeSms(data);
    }
  }

  Future<bool> _handleNativeSms(Map<String, dynamic> data, {bool isRetry = false}) async {
    final sender = (data['sender'] ?? '').toString();
    final message = (data['message'] ?? '').toString();
    final dynamic rawDate = data['date'];
    final dateStr = rawDate.toString();

    try {
      // 1. One Source of Truth: Compute hash using same logic as UI
      // Use Hour-level precision to avoid jitter issues
      String cleanDate = dateStr;
      try {
        final ms = int.tryParse(dateStr) ?? double.parse(dateStr).toInt();
        final dt = DateTime.fromMillisecondsSinceEpoch(ms);
        cleanDate =
            "${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}${dt.hour.toString().padLeft(2, '0')}";
      } catch (_) {}

      final cleanSender = sender.toLowerCase().replaceAll(
        RegExp(r'[^a-z0-9]'),
        '',
      );
      final cleanMessage = message.toLowerCase().replaceAll(
        RegExp(r'[^a-z0-9]'),
        '',
      );

      final raw = '$cleanSender-$cleanDate-$cleanMessage';
      final hash = sha256.convert(utf8.encode(raw)).toString();

      var url = await FlutterForegroundTask.getData<String>(key: 'backend_url');
      var token = await FlutterForegroundTask.getData<String>(
        key: 'access_token',
      );
      final deviceId =
          await FlutterForegroundTask.getData<String>(key: 'device_id') ??
          'Native_Bridge';

      // Fallback to SharedPreferences if isolate storage is empty
      if (url == null || token == null) {
        final prefs = await SharedPreferences.getInstance();
        url ??= prefs.getString('backend_url');
        token ??= prefs.getString('access_token');
      }

      if (url == null || token == null) {
        return false;
      }

      // 2. Fetch Location (Mandatory for "Pro" implementation)
      double? lat = data['latitude'] as double?;
      double? lng = data['longitude'] as double?;

      if (lat == null) {
        try {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
            ),
          ).timeout(const Duration(seconds: 10));
          lat = position.latitude;
          lng = position.longitude;
        } catch (e) {
          // Location fetch failed, proceeding without location
        }
      }

      // 3. Retry Logic (5 times as requested)
      final payload = {
        'sender': sender,
        'message': message,
        'date': rawDate,
        'hash': hash,
        'device_id': deviceId,
        'latitude': lat,
        'longitude': lng,
      };

      int attempts = 0;
      bool success = false;
      final maxAttempts = isRetry ? 1 : 5;

      while (attempts < maxAttempts && !success) {
        attempts++;
        try {
          final response = await http
              .post(
                Uri.parse('$url/api/v1/mobile/ingestion/sms'),
                headers: {
                  'Authorization': 'Bearer $token',
                  'Content-Type': 'application/json',
                },
                body: jsonEncode(payload),
              )
              .timeout(const Duration(seconds: 15));

          if (response.statusCode == 200 || response.statusCode == 201) {
            success = true;
          } else {
            if (attempts < 5) {
              await Future<void>.delayed(const Duration(seconds: 2));
            }
          }
        } catch (e) {
          if (attempts < 5) {
            await Future<void>.delayed(const Duration(seconds: 2));
          }
        }
      }

      if (success) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        await prefs.setBool('sms_hash_$hash', true);

        // Append to Persistent Journal (100% Process Safe & Scalable)
        try {
          final rootPath =
              _resolvedFilesPath ?? '/data/user/0/com.wealthfam.mobile_app';
          final dir = Directory('$rootPath/files');
          if (!await dir.exists()) await dir.create(recursive: true);
          final journal = File('${dir.path}/synced_hashes.db');
          await journal.writeAsString(
            '$hash\n',
            mode: FileMode.append,
            flush: true,
          );
        } catch (e) {
          // Journal write failed, not critical as SharedPreferences is updated
        }

        await FlutterForegroundTask.updateService(
          notificationTitle: 'SMS Synced',
          notificationText: 'Processed message from $sender',
        );

        // Notify Main Isolate for real-time UI update
        FlutterForegroundTask.sendDataToMain({
          'type': 'sms_synced',
          'hash': hash,
        });
        return true;
      } else {
        if (!isRetry) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.reload();
          final offlineQueue = prefs.getStringList('sms_offline_queue') ?? [];
          offlineQueue.add(jsonEncode(payload));
          await prefs.setStringList('sms_offline_queue', offlineQueue);
        }
        return !isRetry; // If retry, return false so caller keeps it in queue
      }
    } catch (e) {
      // General handling failure
      return false;
    }
  }

  @override
  @pragma('vm:entry-point')
  void onNotificationButtonPressed(String id) async {
    if (id == 'toggle_mask') {
      final currentFactor =
          await FlutterForegroundTask.getData<double>(key: 'masking_factor') ??
          1.0;
      final newFactor = currentFactor > 1.0 ? 1.0 : 500000.0;

      await FlutterForegroundTask.saveData(
        key: 'masking_factor',
        value: newFactor,
      );

      // Notify Main Isolate
      FlutterForegroundTask.sendDataToMain({
        'type': 'masking_update',
        'value': newFactor,
      });

      _updateNotificationAsync();
    } else if (id == 'refresh') {
      _updateNotificationAsync();
    }
  }

  @override
  @pragma('vm:entry-point')
  void onNotificationDismissed() {
    _updateNotificationAsync();
  }

  @override
  @pragma('vm:entry-point')
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _timer?.cancel();
    if (isTimeout) {
      // Bug 3 Fix: Self-healing. If system killed us due to timeout, try to restart.
      await FlutterForegroundTask.restartService();
    }
  }

  @pragma('vm:entry-point')
  void _updateNotificationAsync() {
    () async {
      try {
        final url = await FlutterForegroundTask.getData<String>(
          key: 'backend_url',
        );
        final token = await FlutterForegroundTask.getData<String>(
          key: 'access_token',
        );

        if (url == null || token == null) {
          return;
        }

        final response = await http
            .get(
              Uri.parse('$url/api/v1/mobile/mobile-summary'),
              headers: {'Authorization': 'Bearer $token'},
            )
            .timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final rawToday = (data['today_total'] as num? ?? 0.0).toDouble();
          final rawMonth = (data['monthly_total'] as num? ?? 0.0).toDouble();

          final maskingFactor =
              await FlutterForegroundTask.getData<double>(
                key: 'masking_factor',
              ) ??
              1.0;

          final today = (rawToday / maskingFactor).toStringAsFixed(0);
          final month = (rawMonth / maskingFactor).toStringAsFixed(0);

          const symbol = '₹';
          final time = DateTime.now();
          final timeStr =
              '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

          await FlutterForegroundTask.updateService(
            notificationTitle: 'WealthFam Guard',
            notificationText:
                'Today: $symbol$today • Month: $symbol$month\nLast Updated: $timeStr',
          );

          // --- PUSH NOTIFICATION POLLING ---
          final alertsResponse = await http
              .get(
                Uri.parse('$url/api/v1/mobile/alerts'),
                headers: {'Authorization': 'Bearer $token'},
              )
              .timeout(const Duration(seconds: 5));

          if (alertsResponse.statusCode == 200) {
            final alerts = jsonDecode(alertsResponse.body) as List<dynamic>;
            if (alerts.isNotEmpty) {
              final FlutterLocalNotificationsPlugin alertsPlugin =
                  FlutterLocalNotificationsPlugin();
              const AndroidInitializationSettings androidSettings =
                  AndroidInitializationSettings('ic_notification');
              await alertsPlugin.initialize(
                const InitializationSettings(android: androidSettings),
              );

              for (var alertRaw in alerts) {
                final alert = alertRaw as Map<String, dynamic>;
                final title = alert['title'] as String? ?? 'Alert';
                final body = alert['body'] as String? ?? '';
                final dynamic rawId = alert['id'];
                final int id =
                    (rawId is int
                        ? rawId
                        : (rawId?.toString().hashCode ??
                              DateTime.now().millisecondsSinceEpoch)) %
                    2147483647;

                await alertsPlugin.show(
                  id,
                  '🔔 $title',
                  body,
                  const NotificationDetails(
                    android: AndroidNotificationDetails(
                      'wealthfam_alerts',
                      'WealthFam Alerts',
                      channelDescription: 'Real-time financial alerts',
                      importance: Importance.max,
                      priority: Priority.high,
                    ),
                  ),
                );
              }
            }
          }
        } else {
          // Summary fetch failed
        }
      } catch (e) {
        // Notification update cycle failed
      }
    }();
  }
}
