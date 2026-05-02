import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:mobile_app/core/config/app_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telephony/telephony.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_app/modules/auth/services/auth_service.dart';

import 'package:mobile_app/core/services/foreground_service.dart';
import 'package:mobile_app/core/utils/logger.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';

extension PlatformCheck on TargetPlatform {
  bool get shouldUseTelephony => this == TargetPlatform.android;
}

// Top-level background execution is now handled natively in Kotlin (SmsReceiver.kt)

class SmsService extends ChangeNotifier {
  final AppConfig _config;
  final AuthService _auth;

  final Telephony _telephony = Telephony.instance;
  late SharedPreferences _prefs;

  bool _isSyncEnabled = true;
  bool _isForegroundServiceEnabled = false;

  // Stats
  DateTime? _lastSyncTime;
  int _messagesSyncedToday = 0;
  String? _lastSyncStatus;
  List<Map<String, dynamic>> _debugLogs = [];
  bool _isSyncing = false;
  final Set<String> _syncedHashes = {};
  String? _resolvedFilesPath;

  bool get isSyncEnabled => _isSyncEnabled;
  bool get isForegroundServiceEnabled => _isForegroundServiceEnabled;
  DateTime? get lastSyncTime => _lastSyncTime;
  List<Map<String, dynamic>> get debugLogs => _debugLogs;
  int get messagesSyncedToday => _messagesSyncedToday;
  String? get lastSyncStatus => _lastSyncStatus;
  bool get isSyncing => _isSyncing;
  int get queueCount => _getSafeQueueItems().length;

  List<String> _getSafeQueueItems() {
    try {
      final dynamic raw = _prefs.get(keyQueue);
      if (raw == null) return [];
      if (raw is List) return raw.map((e) => e.toString()).toList();

      return [];
    } catch (e) {
      return [];
    }
  }

  List<Map<String, dynamic>> getQueueItems() {
    final List<String> queue = _getSafeQueueItems();
    return queue.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
  }

  bool isInOfflineQueue(String hash) {
    // Check both the offline retry queue AND the native bridge queue
    final List<String> offlineQueue = _getSafeQueueItems();

    // New individual relay files (Direct File System check)
    final List<String> newRelayItems = [];
    try {
      final rootPath =
          _resolvedFilesPath ?? '/data/user/0/com.wealthfam.mobile_app';
      final directory = Directory('$rootPath/files/sms_relay');
      if (directory.existsSync()) {
        final files = directory.listSync();
        for (var file in files) {
          if (file is File && file.path.endsWith('.json')) {
            newRelayItems.add(file.readAsStringSync());
          }
        }
      }
    } catch (e) {
      AppLogger.warn('SmsService: Error listing relay directory: $e');
    }

    final allItems = [...offlineQueue, ...newRelayItems];

    return allItems.any((item) {
      try {
        final decoded = jsonDecode(item);
        final itemHash =
            decoded['hash'] ??
            _computeHash(
              (decoded['address'] ?? decoded['sender'] ?? '').toString(),
              (decoded['date']).toString(),
              (decoded['body'] ?? decoded['message'] ?? '').toString(),
            );
        return itemHash == hash;
      } catch (_) {
        return false;
      }
    });
  }

  // Metadata cache: hash -> {'lat': double, 'lng': double, 'time': int}
  final Map<String, Map<String, dynamic>> _smsMetadata = {};

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _retryTimer;

  bool _isRequestingPermission = false;

  SmsService(this._config, this._auth);

  Future<bool> _requestSmsPermission() async {
    if (_isRequestingPermission) {
      // Wait for the active request to complete
      while (_isRequestingPermission) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return (await Permission.sms.status).isGranted;
    }

    try {
      _isRequestingPermission = true;
      var status = await Permission.sms.status;
      if (status.isGranted) return true;

      status = await Permission.sms.request();
      return status.isGranted;
    } finally {
      _isRequestingPermission = false;
    }
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _isSyncEnabled = _prefs.getBool('is_sync_enabled') ?? true;
    _isForegroundServiceEnabled = _prefs.getBool('fg_service_enabled') ?? false;
    _messagesSyncedToday = _prefs.getInt('msgs_synced_today') ?? 0;
    final lastSyncMs = _prefs.getInt('last_sync_time');
    if (lastSyncMs != null) {
      _lastSyncTime = DateTime.fromMillisecondsSinceEpoch(lastSyncMs);
      final now = DateTime.now();
      if (_lastSyncTime!.day != now.day ||
          _lastSyncTime!.month != now.month ||
          _lastSyncTime!.year != now.year) {
        _messagesSyncedToday = 0;
        _prefs.setInt('msgs_synced_today', 0);
      }
    }

    _loadDebugLogs();

    // Resolve absolute path dynamically
    try {
      final appDir = await getApplicationSupportDirectory();
      _resolvedFilesPath = appDir.parent.path;
    } catch (e) {
      AppLogger.error('SmsService: Directory resolution failed', e);
      _resolvedFilesPath = '/data/user/0/com.wealthfam.mobile_app';
    }

    await _loadSyncedHashesJournal();

    if (kIsWeb || !defaultTargetPlatform.shouldUseTelephony) {
      AppLogger.info("SMS features disabled: Not on Android.");
      return;
    }

    final isGranted = await _requestSmsPermission();
    if (isGranted) {
      // Also request location permissions to ensure we can send location with SMS
      await _requestLocationPermissions();

      // Always save credentials for background listener if authenticated
      if (_auth.accessToken != null) {
        await _saveCredentials();
      }

      _startListening();
      AppLogger.info("SmsService: Real-time SMS Listener Started.");

      if (_isForegroundServiceEnabled && _auth.accessToken != null) {
        ForegroundServiceWrapper.start(
          url: _config.backendUrl,
          token: _auth.accessToken!,
          deviceId: _auth.deviceId,
        );
      }

      // Retry any queued messages from previous sessions
      retryQueue();

      // Listen for connectivity changes to auto-retry
      _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
        results,
      ) {
        final hasConnection = results.any((r) => r != ConnectivityResult.none);
        if (hasConnection && queueCount > 0) {
          AppLogger.info("Connectivity regained, retrying SMS queue...");
          retryQueue();
        }
      });

      // Periodic retry every 5 minutes
      _retryTimer = Timer.periodic(
        const Duration(minutes: 5),
        (_) => retryQueue(),
      );
    }

    // Listen for config changes (e.g. backend URL update)
    _config.addListener(_handleConfigChange);
  }

  void _loadDebugLogs() {
    final savedLogs = _prefs.getStringList('sms_debug_logs');
    if (savedLogs != null) {
      _debugLogs = savedLogs
          .map((e) => jsonDecode(e) as Map<String, dynamic>)
          .toList();
    }
  }

  void refreshDebugLogs() {
    _loadDebugLogs();
    notifyListeners();
  }

  void _handleConfigChange() {
    if (_isForegroundServiceEnabled && _auth.accessToken != null) {
      AppLogger.info(
        "SmsService: Config changed, updating foreground service...",
      );
      _saveCredentials();
      ForegroundServiceWrapper.start(
        url: _config.backendUrl,
        token: _auth.accessToken!,
        deviceId: _auth.deviceId,
      );
    }
  }

  @override
  void dispose() {
    _config.removeListener(_handleConfigChange);
    _connectivitySubscription?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }

  Future<void> _saveSmsMetadata(
    String hash,
    double? lat,
    double? lng,
    int date,
  ) async {
    _smsMetadata[hash] = {'hash': hash, 'lat': lat, 'lng': lng, 'date': date};
    final items = _smsMetadata.values.map((e) => jsonEncode(e)).toList();
    // Keep only last 200 items to avoid pref bloat
    if (items.length > 200) {
      final keys = _smsMetadata.keys.toList();
      _smsMetadata.remove(keys.first);
    }
    await _prefs.setStringList(
      'sms_metadata_store',
      _smsMetadata.values.map((e) => jsonEncode(e)).toList(),
    );
    notifyListeners();
  }

  Map<String, dynamic>? getMetadata(String hash) => _smsMetadata[hash];

  Future<void> toggleSync(bool enabled) async {
    _isSyncEnabled = enabled;
    await _prefs.setBool('is_sync_enabled', enabled);
    if (enabled) {
      retryQueue();
    }
    notifyListeners();
  }

  Future<void> toggleForegroundService(bool enabled) async {
    _isForegroundServiceEnabled = enabled;
    await _prefs.setBool('fg_service_enabled', enabled);

    if (enabled) {
      if (_auth.accessToken == null) {
        _isForegroundServiceEnabled = false;
        await _prefs.setBool('fg_service_enabled', false);
        notifyListeners();
        throw Exception("Authentication required to start sync service");
      }
      await _saveCredentials();

      // Attempt to start - on Android 14+ this may return false but still start successfully
      await ForegroundServiceWrapper.start(
        url: _config.backendUrl,
        token: _auth.accessToken!,
        deviceId: _auth.deviceId,
      );
      // Don't throw error based on return value - Android 14+ often returns false even on success
    } else {
      await ForegroundServiceWrapper.stop();
    }
    notifyListeners();
  }

  Future<void> _requestLocationPermissions() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        AppLogger.info("Location permissions granted");
      }
    } catch (e) {
      AppLogger.error("Error requesting location permissions", e);
    }
  }

  void _startListening() {
    // Real-time interception is now handled by Native Kotlin (SmsReceiver.kt).
    // The native receiver writes directly to the shared queue and pushes to backend.
    // We no longer need a foreground Dart listener which would cause duplicates.
    AppLogger.info(
      "SmsService: Real-time listening delegated to Native Bridge.",
    );
  }

  // processSms is still used for manual imports/scans
  Future<Map<String, dynamic>> processSms(
    String address,
    String body,
    int date, {
    double? lat,
    double? lng,
  }) async {
    if (!_isSyncEnabled) {
      return {'status': 'disabled', 'reason': 'Sync disabled'};
    }

    final String hash = _computeHash(address, date.toString(), body);

    // Always update metadata cache if we have new coordinates
    if (lat != null || !_smsMetadata.containsKey(hash)) {
      await _saveSmsMetadata(hash, lat, lng, date);
    }

    if (_isCached(hash)) {
      return {'status': 'cached', 'hash': hash};
    }

    // Bug 2 Fix: Store-and-Forward (Write-first)
    // Queue immediately before trying network
    final metadata = _smsMetadata[hash];
    await _queueForRetry(
      address,
      body,
      date,
      lat: lat ?? metadata?['lat'],
      lng: lng ?? metadata?['lng'],
    );

    try {
      final res = await _sendToBackend(address, body, date, lat: lat, lng: lng);

      // Success! Mark cached and remove from queue
      await _cacheHash(hash);
      _updateSyncStats(true);

      // Dequeue
      final List<String> queue = _getSafeQueueItems();
      queue.removeWhere((item) {
        try {
          final decoded = jsonDecode(item);
          return _computeHash(
                decoded['address'],
                decoded['date'].toString(),
                decoded['body'],
              ) ==
              hash;
        } catch (_) {
          return false;
        }
      });
      await _prefs.setStringList(keyQueue, queue);

      return res;
    } catch (e) {
      AppLogger.error("Failed to send SMS to backend", e);
      _updateSyncStats(false);
      rethrow; // Stay in queue for retry later
    }
  }

  String computeHash(String address, String dateStr, String body) {
    // Robust Normalization: Use Hour-level precision to avoid jitter issues
    String cleanDate = dateStr;
    try {
      final ms = int.tryParse(dateStr) ?? double.parse(dateStr).toInt();
      final dt = DateTime.fromMillisecondsSinceEpoch(ms);
      // Format: YYYYMMDDHH
      cleanDate =
          "${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}${dt.hour.toString().padLeft(2, '0')}";
    } catch (_) {
      // Fallback to original if parse fails
    }

    // Aggressive Normalization: Strip everything except letters and numbers
    final cleanAddress = address.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]'),
      '',
    );
    final cleanBody = body.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

    final raw = "$cleanAddress-$cleanDate-$cleanBody";
    return sha256.convert(utf8.encode(raw)).toString();
  }

  String _computeHash(String address, String date, String body) =>
      computeHash(address, date, body);

  bool isCached(String hash) {
    if (_syncedHashes.contains(hash)) return true;

    // Fallback to SharedPreferences
    return _prefs.containsKey('sms_hash_$hash');
  }

  bool _isCached(String hash) => isCached(hash);

  Future<void> _loadSyncedHashesJournal() async {
    try {
      final rootPath =
          _resolvedFilesPath ?? '/data/user/0/com.wealthfam.mobile_app';
      final journal = File('$rootPath/files/synced_hashes.db');
      if (await journal.exists()) {
        final lines = await journal.readAsLines();
        _syncedHashes.addAll(lines.where((l) => l.isNotEmpty));
      }
    } catch (e) {
      AppLogger.warn("SmsService: Journal load failed: $e");
    }
  }

  Future<void> cacheHash(String hash) async {
    if (_syncedHashes.contains(hash)) return;

    _syncedHashes.add(hash);

    // Append to Persistent Journal (Scalable & Process Safe)
    try {
      final rootPath =
          _resolvedFilesPath ?? '/data/user/0/com.wealthfam.mobile_app';
      final dir = Directory('$rootPath/files');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final journal = File('${dir.path}/synced_hashes.db');
      await journal.writeAsString(
        '$hash\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (e) {
      AppLogger.warn('SmsService: Journal write failed: $e');
    }

    await _prefs.setBool('sms_hash_$hash', true);
    notifyListeners();
  }

  Future<void> _cacheHash(String hash) async => cacheHash(hash);

  // Ensure credentials are saved for Background Isolate
  Future<void> _saveCredentials() async {
    await _prefs.setString('backend_url', _config.backendUrl);
    await _prefs.setString('device_id', _auth.deviceId ?? 'unknown');
    if (_auth.accessToken != null) {
      await _prefs.setString('access_token', _auth.accessToken!);
    }
  }

  Future<void> clearCache() async {
    final keys = _prefs.getKeys().where((k) => k.startsWith('sms_hash_'));
    for (final key in keys) {
      await _prefs.remove(key);
    }
    notifyListeners();
  }

  Future<Map<String, dynamic>> _sendToBackend(
    String address,
    String body,
    int date, {
    double? lat,
    double? lng,
  }) async {
    if (!_auth.isAuthenticated || _auth.accessToken == null) {
      throw Exception("Not Authenticated");
    }

    // Get Location if possible
    double? finalLat = lat;
    double? finalLng = lng;

    if (finalLat == null) {
      try {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.whileInUse ||
            permission == LocationPermission.always) {
          Position? position = await Geolocator.getLastKnownPosition();
          position ??= await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
            ),
          ).timeout(const Duration(seconds: 5));

          finalLat = position.latitude;
          finalLng = position.longitude;
        }
      } catch (e) {
        AppLogger.warn("SmsService: Error getting location: $e");
      }
    }

    final url = Uri.parse('${_config.backendUrl}/api/v1/ingestion/sms');
    final hash = _computeHash(address, date.toString(), body);

    final payload = {
      'sender': address,
      'message': body,
      'date': date,
      'hash': hash,
      'device_id': _auth.deviceId,
      'latitude': finalLat,
      'longitude': finalLng,
    };

    int attempts = 0;
    Exception? lastError;

    while (attempts < 5) {
      attempts++;
      try {
        AppLogger.debug("SmsService: Sync attempt $attempts for $hash");
        final response = await http
            .post(
              url,
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer ${_auth.accessToken}',
              },
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 15));

        if (response.statusCode == 200 || response.statusCode == 201) {
          if (_config.sendDebugPayload) {
            _debugLogs.insert(0, payload);
            if (_debugLogs.length > 10) _debugLogs.removeLast();
            await _prefs.setStringList(
              'sms_debug_logs',
              _debugLogs.map((e) => jsonEncode(e)).toList(),
            );
          }
          return jsonDecode(response.body);
        } else {
          final detail = jsonDecode(response.body)['detail'] ?? 'Backend Error';
          lastError = Exception("$detail (${response.statusCode})");
          if (attempts < 5) await Future.delayed(const Duration(seconds: 2));
        }
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        if (attempts < 5) await Future.delayed(const Duration(seconds: 2));
      }
    }

    throw lastError ?? Exception("Failed after 5 attempts");
  }

  // --- Offline Queue Logic ---
  static const String keyQueue = 'sms_offline_queue';

  Future<void> _queueForRetry(
    String address,
    String body,
    int date, {
    double? lat,
    double? lng,
  }) async {
    final List<String> queue = _getSafeQueueItems();

    final item = {
      'address': address,
      'body': body,
      'date': date,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'latitude': lat,
      'longitude': lng,
    };

    queue.add(jsonEncode(item));
    await _prefs.setStringList(keyQueue, queue);
    notifyListeners();
  }

  bool _isRetrying = false;

  Future<void> retryQueue() async {
    if (_isRetrying) return;
    await _prefs.reload();
    final List<String> queue = _getSafeQueueItems();
    if (queue.isEmpty) return;

    _isRetrying = true;
    notifyListeners();

    final List<String> remaining = [];
    int successCount = 0;

    try {
      for (final itemStr in queue) {
        try {
          final item = jsonDecode(itemStr);
          final address = item['address'];
          final body = item['body'];
          final date = item['date'];

          final hash = _computeHash(address, date.toString(), body);
          if (!_isCached(hash)) {
            await _sendToBackend(
              address,
              body,
              date,
              lat: item['latitude'] as double?,
              lng: item['longitude'] as double?,
            );
            await _cacheHash(hash);
          }
          successCount++;
          _updateSyncStats(true);
        } catch (e) {
          remaining.add(itemStr);
        }
      }

      await _prefs.setStringList(keyQueue, remaining);
    } finally {
      _isRetrying = false;
      if (successCount > 0 || remaining.length != queue.length) {
        notifyListeners();
      }
    }
  }

  Future<void> syncNow() async {
    if (_isSyncing) return;
    _isSyncing = true;
    _lastSyncStatus = "Syncing...";
    notifyListeners();

    try {
      // 1. Retry failed ones
      await retryQueue();

      // 2. Scan recent inbox (last 72 hours) for missed ones
      await syncLastHours(72);

      _lastSyncStatus = "Success";
    } catch (e) {
      _lastSyncStatus = "Failed";
      AppLogger.error("Manual Sync Error", e);
    } finally {
      _isSyncing = false;
      _lastSyncTime = DateTime.now();
      _prefs.setInt('last_sync_time', _lastSyncTime!.millisecondsSinceEpoch);
      notifyListeners();
    }
  }

  // --- Manual Sync ---

  Future<void> syncUnsyncedOnStart() async {
    if (kIsWeb || !defaultTargetPlatform.shouldUseTelephony) return;

    // Delay startup scan to let the main UI load and background task stabilize
    Future.delayed(const Duration(seconds: 10), () async {
      AppLogger.info(
        "SmsService: Starting background sync of recent messages (24h window)...",
      );
      await syncLastHours(24);
    });
  }

  Future<int> pushAllUnsynced() async {
    if (kIsWeb || !defaultTargetPlatform.shouldUseTelephony) return 0;

    final messages = await _telephony.getInboxSms(
      columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
    );

    int pushed = 0;
    for (final msg in messages) {
      if (msg.body == null || msg.address == null || msg.date == null) continue;

      final hash = _computeHash(msg.address!, msg.date.toString(), msg.body!);
      if (!_isCached(hash)) {
        try {
          await _sendToBackend(msg.address!, msg.body!, msg.date!);
          await _cacheHash(hash);
          pushed++;
          _updateSyncStats(true);
        } catch (e) {
          AppLogger.warn("Push all failed for one message: $e");
        }
      }
    }
    return pushed;
  }

  Future<int> syncLastHours(int hours) async {
    final cutoff = DateTime.now().subtract(Duration(hours: hours));
    return syncFromDate(cutoff);
  }

  Future<int> syncFromDate(DateTime fromDate) async {
    if (kIsWeb || !defaultTargetPlatform.shouldUseTelephony) {
      AppLogger.info("Manual Sync skipped: Not on Android.");
      return 0;
    }

    await _prefs.reload();
    notifyListeners(); // Update UI loading state if binding

    final cutoffMs = fromDate.millisecondsSinceEpoch;

    final messages = await _telephony.getInboxSms(
      columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
      filter: SmsFilter.where(
        SmsColumn.DATE,
      ).greaterThanOrEqualTo(cutoffMs.toString()),
    );

    int sent = 0;
    for (final msg in messages) {
      if (msg.body == null || msg.address == null) continue;

      final hash = _computeHash(msg.address!, msg.date.toString(), msg.body!);
      if (!_isCached(hash)) {
        try {
          await _sendToBackend(msg.address!, msg.body!, msg.date ?? 0);
          await _cacheHash(hash);
          sent++;
          _updateSyncStats(true);
        } catch (e) {
          _queueForRetry(msg.address!, msg.body!, msg.date ?? 0);
        }
      }
    }
    return sent;
  }

  Future<List<SmsMessage>> getAllMessages() async {
    if (kIsWeb || !defaultTargetPlatform.shouldUseTelephony) return [];

    await _prefs.reload();
    final isGranted = await _requestSmsPermission();
    if (!isGranted) {
      AppLogger.warn("SmsService: READ_SMS permission denied");
      return [];
    }

    try {
      final msgs = await _telephony.getInboxSms(
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
      );
      // Return only most recent 50 to avoid UI lag
      return msgs.length > 50 ? msgs.sublist(0, 50) : msgs;
    } catch (e) {
      AppLogger.error("Error fetching SMS", e);
      return [];
    }
  }

  Future<List<SmsMessage>> querySpecificAddress(String address) async {
    if (kIsWeb || !defaultTargetPlatform.shouldUseTelephony) return [];
    final isGranted = await _requestSmsPermission();
    if (!isGranted) return [];

    try {
      AppLogger.debug("SmsService: Deep querying for address: $address");
      // Use getInboxSms with like filter for flexibility
      final msgs = await _telephony.getInboxSms(
        filter: SmsFilter.where(SmsColumn.ADDRESS).like("%$address%"),
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
      );
      AppLogger.debug("SmsService: Deep query found ${msgs.length} messages");
      return msgs;
    } catch (e) {
      AppLogger.error("SmsService: Deep query error", e);
      return [];
    }
  }

  Future<Map<String, dynamic>> sendSmsToBackend(
    String address,
    String body,
    int date, {
    double? lat,
    double? lng,
  }) async {
    final res = await _sendToBackend(address, body, date, lat: lat, lng: lng);
    final hash = computeHash(address, date.toString(), body);
    await cacheHash(hash);
    _updateSyncStats(true);
    notifyListeners();
    return res;
  }

  void _updateSyncStats(bool success) {
    _lastSyncTime = DateTime.now();
    _prefs.setInt('last_sync_time', _lastSyncTime!.millisecondsSinceEpoch);

    if (success) {
      _messagesSyncedToday++;
      _prefs.setInt('msgs_synced_today', _messagesSyncedToday);
      _lastSyncStatus = "Success";
    } else {
      _lastSyncStatus = "Failed";
    }
    notifyListeners();
  }

  Future<void> forceRefresh([String? hash]) async {
    if (hash != null) {
      _syncedHashes.add(hash);
    }
    await _prefs.reload();
    notifyListeners();
  }
}
