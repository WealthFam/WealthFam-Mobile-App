import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'package:geolocator/geolocator.dart';
import 'package:telephony/telephony.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';
import 'dart:io';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(SyncTaskHandler());
}

@pragma('vm:entry-point')
class SyncTaskHandler extends TaskHandler {
  int _eventCount = 0;
  Timer? _timer;
  bool _isProcessingQueue = false;
  Position? _lastPosition;
  DateTime? _lastPositionTime;

  String? _resolvedFilesPath;

  @override
  @pragma('vm:entry-point')
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Service started
    
    // Resolve absolute path dynamically
    try {
      final Directory? appDir = await getApplicationSupportDirectory().catchError((_) => null);
      _resolvedFilesPath = appDir?.parent.path ?? '/data/user/0/com.wealthfam.mobile_app';
    } catch (e) {
      _resolvedFilesPath = '/data/user/0/com.wealthfam.mobile_app';
    }

    // Perform a one-time catch-up scan of the last 24h quietly in the background
    _performCatchUpScan(); 
    
    // Start reliable 5s timer for native queue check
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _eventCount++;
      _checkNativeSmsQueue();
      
      // Every 5 minutes: Retry offline queue
      if (_eventCount % 60 == 0) {
        _retryOfflineQueue();
      }
      
      if (_eventCount % 12 == 0) { // Every minute
        _updateNotificationAsync();
      }
    });

    await _checkNativeSmsQueue();
    _updateNotificationAsync();
  }

  Future<void> _retryOfflineQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final List<String> queue = prefs.getStringList('sms_offline_queue') ?? [];
      if (queue.isEmpty) return;

      final List<String> remaining = [];
      for (final itemStr in queue) {
        try {
          final data = jsonDecode(itemStr);
          final success = await _handleNativeSms(data);
          if (!success) remaining.add(itemStr);
        } catch (_) {
          // Keep corrupt items but don't block
          remaining.add(itemStr);
        }
      }
      await prefs.setStringList('sms_offline_queue', remaining);
    } catch (e) {
    }
  }

  Future<void> _performCatchUpScan() async {
    try {
      final Telephony telephony = Telephony.instance;
      final cutoff = DateTime.now().subtract(const Duration(hours: 24)).millisecondsSinceEpoch;
      
      final messages = await telephony.getInboxSms(
        columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
        filter: SmsFilter.where(SmsColumn.DATE).greaterThanOrEqualTo(cutoff.toString()),
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
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
        ).timeout(const Duration(seconds: 10));
        batchLat = pos.latitude;
        batchLng = pos.longitude;
      } catch (_) {}
      
      int syncCount = 0;
      for (final msg in messages) {
        if (msg.address == null || msg.body == null || msg.date == null) continue;
        
        // Use same hashing logic
        final dateStr = msg.date.toString();
        String cleanDate = dateStr;
        try {
          final ms = int.tryParse(dateStr) ?? double.parse(dateStr).toInt();
          final dt = DateTime.fromMillisecondsSinceEpoch(ms);
          cleanDate = "${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}${dt.hour.toString().padLeft(2, '0')}";
        } catch (_) {}
        
        final cleanSender = msg.address!.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        final cleanMessage = msg.body!.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        final raw = "$cleanSender-$cleanDate-$cleanMessage";
        final hash = sha256.convert(utf8.encode(raw)).toString();
        
        if (!prefs.containsKey('sms_hash_$hash')) {
          final success = await _handleNativeSms({
            'sender': msg.address,
            'message': msg.body,
            'date': msg.date,
            'latitude': batchLat,
            'longitude': batchLng,
          });
          if (success) syncCount++;
        }
      }
      
    } catch (e) {
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
      final rootPath = _resolvedFilesPath ?? '/data/user/0/com.wealthfam.mobile_app';
      final directory = Directory('$rootPath/files/sms_relay');
      
      if (!await directory.exists()) {
        _isProcessingQueue = false;
        return;
      }

      final List<FileSystemEntity> files = await directory.list().toList();
      if (files.isEmpty) return;

      
      for (var file in files) {
        if (file is File && file.path.endsWith('.json')) {
          try {
            final String content = await file.readAsString();
            final data = jsonDecode(content);
            
            final success = await _handleNativeSms(data);
            if (success) {
              if (await file.exists()) {
                await file.delete().catchError((_) {});
              }
            }
          } catch (e) {
            if (await file.exists()) {
              await file.delete().catchError((_) {});
            }
          }
        }
      }

      _isProcessingQueue = false;
    } catch (e) {
      _isProcessingQueue = false;
    }
  }

  @override
  @pragma('vm:entry-point')
  void onReceiveData(Object data) {
    if (data is Map && data['type'] == 'sms') {
      _handleNativeSms(data);
    }
  }

  Future<bool> _handleNativeSms(Map data) async {
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
        cleanDate = "${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}${dt.hour.toString().padLeft(2, '0')}";
      } catch (_) {}

      final cleanSender = sender.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      final cleanMessage = message.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      
      final raw = "$cleanSender-$cleanDate-$cleanMessage";
      final hash = sha256.convert(utf8.encode(raw)).toString();
      

      final url = await FlutterForegroundTask.getData<String>(key: 'backend_url');
      final token = await FlutterForegroundTask.getData<String>(key: 'access_token');
      final deviceId = await FlutterForegroundTask.getData<String>(key: 'device_id') ?? 'Native_Bridge';

      if (url == null || token == null) {
        return false;
      }

      // 2. Fetch Location (Mandatory for "Pro" implementation)
      double? lat = data['latitude'] as double?;
      double? lng = data['longitude'] as double?;
      
      if (lat == null) {
        try {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
          ).timeout(const Duration(seconds: 10));
          lat = position.latitude;
          lng = position.longitude;
        } catch (e) {
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
      
      while (attempts < 5 && !success) {
        attempts++;
        try {
          final response = await http.post(
            Uri.parse('$url/api/v1/ingestion/sms'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          ).timeout(const Duration(seconds: 15));

          if (response.statusCode == 200 || response.statusCode == 201) {
            success = true;
          } else {
            if (attempts < 5) await Future.delayed(const Duration(seconds: 2));
          }
        } catch (e) {
          if (attempts < 5) await Future.delayed(const Duration(seconds: 2));
        }
      }

      if (success) {
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        await prefs.setBool('sms_hash_$hash', true);

        // Append to Persistent Journal (100% Process Safe & Scalable)
        try {
          final rootPath = _resolvedFilesPath ?? '/data/user/0/com.wealthfam.mobile_app';
          final dir = Directory('$rootPath/files');
          if (!await dir.exists()) await dir.create(recursive: true);
          final journal = File('${dir.path}/synced_hashes.db');
          await journal.writeAsString('$hash\n', mode: FileMode.append, flush: true);
        } catch (e) {
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
        final offlineQueue = prefs.getStringList('sms_offline_queue') ?? [];
        offlineQueue.add(jsonEncode(payload));
        await prefs.setStringList('sms_offline_queue', offlineQueue);
        return true; // Mark as processed from native queue so we don't loop forever
      }
    } catch (e, stack) {
      return false; 
    }
  }

  @override
  @pragma('vm:entry-point')
  void onNotificationButtonPressed(String id) async {
    if (id == 'toggle_mask') {
      final currentFactor = await FlutterForegroundTask.getData<double>(key: 'masking_factor') ?? 1.0;
      final newFactor = currentFactor > 1.0 ? 1.0 : 500000.0; 
      
      await FlutterForegroundTask.saveData(key: 'masking_factor', value: newFactor);
      
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
        final url = await FlutterForegroundTask.getData<String>(key: 'backend_url');
        final token = await FlutterForegroundTask.getData<String>(key: 'access_token');
        
        if (url == null || token == null) {
          return;
        }

        final response = await http.get(
          Uri.parse('$url/api/v1/mobile/mobile-summary'),
          headers: {'Authorization': 'Bearer $token'},
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final rawToday = (data['today_total'] ?? 0.0).toDouble();
          final rawMonth = (data['monthly_total'] ?? 0.0).toDouble();
          
          final maskingFactor = await FlutterForegroundTask.getData<double>(key: 'masking_factor') ?? 1.0;
          
          final today = (rawToday / maskingFactor).toStringAsFixed(0);
          final month = (rawMonth / maskingFactor).toStringAsFixed(0);
          
          final symbol = '₹';
          final time = DateTime.now();
          final timeStr = "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}";

          await FlutterForegroundTask.updateService(
            notificationTitle: 'WealthFam Guard',
            notificationText: 'Today: $symbol$today • Month: $symbol$month\nLast Updated: $timeStr',
          );

          // --- PUSH NOTIFICATION POLLING ---
          final alertsResponse = await http.get(
            Uri.parse('$url/api/v1/mobile/alerts'),
            headers: {'Authorization': 'Bearer $token'},
          ).timeout(const Duration(seconds: 5));

          if (alertsResponse.statusCode == 200) {
            final List alerts = jsonDecode(alertsResponse.body);
            if (alerts.isNotEmpty) {
              final FlutterLocalNotificationsPlugin alertsPlugin = FlutterLocalNotificationsPlugin();
              const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('ic_notification');
              await alertsPlugin.initialize(const InitializationSettings(android: androidSettings));

              for (var alert in alerts) {
                final title = alert['title'] ?? 'Alert';
                final body = alert['body'] ?? '';
                final dynamic rawId = alert['id'];
                final int id = (rawId is int ? rawId : (rawId?.toString().hashCode ?? DateTime.now().millisecondsSinceEpoch)) % 2147483647;
                
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
                      playSound: true,
                      autoCancel: true,
                    ),
                  ),
                );
              }
            }
          }
        } else {
        }
      } catch (e) {
      }
    }();
  }
}
