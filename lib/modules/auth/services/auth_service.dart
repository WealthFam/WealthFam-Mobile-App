import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_app/core/config/app_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService extends ChangeNotifier {
  final AppConfig _config;
  final _storage = const FlutterSecureStorage();

  bool _isAuthenticated = false;
  String? _accessToken;
  String? _tenantId;
  String? _deviceId;
  String? _deviceName;
  String? _userRole;
  String? _userName;
  String? _userAvatar;
  bool _isApproved = false;

  bool get isAuthenticated => _isAuthenticated;
  bool get isApproved => _isApproved;
  String? get accessToken => _accessToken;
  String? get deviceId => _deviceId;
  String? get userRole => _userRole;
  String? get userName => _userName;
  String? get userAvatar => _userAvatar;
  String? get tenantId => _tenantId;

  AuthService(this._config);

  Future<void> init() async {
    _accessToken = await _storage.read(key: 'access_token');
    _tenantId = await _storage.read(key: 'tenant_id');
    _deviceId = await _storage.read(key: 'device_id');
    _deviceName = await _storage.read(key: 'device_name');
    _userRole = await _storage.read(key: 'user_role');
    _userName = await _storage.read(key: 'user_name');
    _userAvatar = await _storage.read(key: 'user_avatar');

    if (_deviceId == null || _deviceName == null) {
      await _initDeviceInfo();
    }

    if (_accessToken != null) {
      _isAuthenticated = true;
      try {
        await checkStatus();
        _startHeartbeat();
      } catch (e) {
        debugPrint('Offline or Check Status Failed: $e');
      }
    }
    notifyListeners();
  }

  Future<void> _initDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    if (kIsWeb) {
      _deviceId = 'web-client-${DateTime.now().millisecondsSinceEpoch}';
      _deviceName = 'Web Client';
    } else if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      _deviceId = androidInfo.id; // Unique ID
      _deviceName = '${androidInfo.brand} ${androidInfo.model}';
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      _deviceId = iosInfo.identifierForVendor;
      _deviceName = '${iosInfo.name} ${iosInfo.model}';
    } else if (Platform.isWindows) {
      final winInfo = await deviceInfo.windowsInfo;
      _deviceId = winInfo.deviceId;
      _deviceName = winInfo.computerName;
    } else {
      _deviceId = 'unknown-${DateTime.now().millisecondsSinceEpoch}';
      _deviceName = 'Unknown Device';
    }

    // Ensure we always have a device name fallback
    _deviceName ??= 'Mobile Device';

    await _storage.write(key: 'device_id', value: _deviceId);
    await _storage.write(key: 'device_name', value: _deviceName);
    debugPrint('Device Info initialized: ID=$_deviceId, Name=$_deviceName');
  }

  Future<void> setDeviceId(String id) async {
    _deviceId = id;
    await _storage.write(key: 'device_id', value: id);
    notifyListeners();
  }

  Future<void> login(String username, String password) async {
    if (_deviceId == null) await _initDeviceInfo();

    final url = Uri.parse('${_config.backendUrl}/api/v1/mobile/login');

    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username': username,
              'password': password,
              'device_id': _deviceId,
              'device_name': _deviceName,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _accessToken = data['access_token'];
        _isApproved = data['device_status']['is_approved'];
        _tenantId = data['device_status']['tenant_id'];
        _userRole = data['user_role'];

        await _storage.write(key: 'access_token', value: _accessToken);
        await _storage.write(key: 'tenant_id', value: _tenantId);
        if (_userRole != null) {
          await _storage.write(key: 'user_role', value: _userRole);
        }
        _userName = data['user_name'];
        _userAvatar = data['user_avatar'];
        if (_userName != null) {
          await _storage.write(key: 'user_name', value: _userName);
        }
        if (_userAvatar != null) {
          await _storage.write(key: 'user_avatar', value: _userAvatar);
        }

        _isAuthenticated = true;
        _startHeartbeat();
        notifyListeners();
      } else {
        throw Exception(
          'Login Failed: ${response.statusCode} ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('Login Error: $e');
      rethrow;
    }
  }

  Future<void> logout() async {
    try {
      if (_accessToken != null) {
        final url = Uri.parse('${_config.backendUrl}/api/v1/auth/logout');
        await http
            .post(
              url,
              headers: {
                'Authorization': 'Bearer $_accessToken',
                'Content-Type': 'application/json',
              },
            )
            .timeout(const Duration(seconds: 5));
      }
    } catch (e) {
      debugPrint('Logout API call failed (ignoring): $e');
    }

    _isAuthenticated = false;
    _accessToken = null;
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'tenant_id');
    await _storage.delete(key: 'user_name');
    await _storage.delete(key: 'user_avatar');
    _userName = null;
    _userAvatar = null;
    _isApproved = false;
    stopHeartbeat();

    // Clear mirrored credentials for Native Bridge
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('backend_url');
    await prefs.remove('access_token');

    notifyListeners();
  }

  Future<void> checkStatus() async {
    if (_accessToken == null || _deviceId == null) {
      return;
    }

    final url = Uri.parse(
      '${_config.backendUrl}/api/v1/mobile/status?device_id=$_deviceId',
    );
    try {
      final response = await http
          .get(url, headers: {'Authorization': 'Bearer $_accessToken'})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _isApproved = data['is_approved'];
        _userName = data['user_name'];
        _userAvatar = data['user_avatar'];
        if (_userName != null) {
          await _storage.write(key: 'user_name', value: _userName);
        }
        if (_userAvatar != null) {
          await _storage.write(key: 'user_avatar', value: _userAvatar);
        }
        notifyListeners();
      } else if (response.statusCode == 401) {
        await logout();
      }
    } catch (e) {
      debugPrint('Status check failed: $e');
    }
  }

  // --- Heartbeat Logic ---
  Timer? _heartbeatTimer;

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      if (_isAuthenticated && _accessToken != null) {
        sendHeartbeat();
      } else {
        timer.cancel();
      }
    });
  }

  void stopHeartbeat() {
    _heartbeatTimer?.cancel();
  }

  Future<void> sendHeartbeat() async {
    if (_accessToken == null || _deviceId == null) return;

    final url = Uri.parse(
      '${_config.backendUrl}/api/v1/mobile/heartbeat?device_id=$_deviceId',
    );
    try {
      final response = await http
          .post(
            url,
            headers: {
              'Authorization': 'Bearer $accessToken',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (_isApproved != data['is_approved']) {
          _isApproved = data['is_approved'];
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Heartbeat failed: $e');
    }
  }
}
