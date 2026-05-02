import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppConfig extends ChangeNotifier {
  static const String keyBackendUrl = 'backend_url';
  static const String keyWebUiUrl = 'web_ui_url';
  static const String keySendDebugPayload = 'show_debug_payload';

  static const String defaultBackendUrl = 'http://192.168.0.7:8000';
  static const String defaultWebUiUrl = 'http://192.168.0.7:80';

  late SharedPreferences _prefs;
  bool _initialized = false;

  String _backendUrl = defaultBackendUrl;
  String _webUiUrl = defaultWebUiUrl;
  bool _sendDebugPayload = false;

  String get backendUrl => _backendUrl;
  String get webUiUrl => _webUiUrl;
  bool get sendDebugPayload => _sendDebugPayload;
  bool get isInitialized => _initialized;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _backendUrl = _prefs.getString(keyBackendUrl) ?? defaultBackendUrl;
    _webUiUrl = _prefs.getString(keyWebUiUrl) ?? defaultWebUiUrl;
    _sendDebugPayload = _prefs.getBool(keySendDebugPayload) ?? false;
    _initialized = true;
    notifyListeners();
  }

  Future<void> setBackendUrl(String value) async {
    // Strip trailing slash
    if (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    _backendUrl = value;
    await _prefs.setString(keyBackendUrl, value);
    notifyListeners();
  }

  Future<void> setWebUiUrl(String value) async {
    if (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    _webUiUrl = value;
    await _prefs.setString(keyWebUiUrl, value);
    notifyListeners();
  }

  Future<void> setDebugPayload(bool value) async {
    _sendDebugPayload = value;
    await _prefs.setBool(keySendDebugPayload, value);
    notifyListeners();
  }

  Future<void> setUrls({required String backend, required String webUi}) async {
    // Strip trailing slashes
    if (backend.endsWith('/')) {
      backend = backend.substring(0, backend.length - 1);
    }
    if (webUi.endsWith('/')) {
      webUi = webUi.substring(0, webUi.length - 1);
    }

    _backendUrl = backend;
    _webUiUrl = webUi;

    await _prefs.setString(keyBackendUrl, backend);
    await _prefs.setString(keyWebUiUrl, webUi);
    notifyListeners();
  }
}
