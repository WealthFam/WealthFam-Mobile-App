import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screen_protector/screen_protector.dart';

class SecurityService extends ChangeNotifier {
  final LocalAuthentication _auth = LocalAuthentication();
  late SharedPreferences _prefs;
  
  bool _isBiometricEnabled = false;
  bool _isPrivacyEnabled = true;
  bool _isAuthenticated = false;

  bool get isBiometricEnabled => _isBiometricEnabled;
  bool get isPrivacyEnabled => _isPrivacyEnabled;
  bool get isAuthenticated => _isAuthenticated;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _isBiometricEnabled = _prefs.getBool('biometric_enabled') ?? false;
    _isPrivacyEnabled = _prefs.getBool('privacy_enabled') ?? true;
    
    if (_isPrivacyEnabled) {
      await ScreenProtector.protectDataLeakageOn();
    } else {
      await ScreenProtector.protectDataLeakageOff();
    }
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    _isBiometricEnabled = enabled;
    await _prefs.setBool('biometric_enabled', enabled);
    notifyListeners();
  }

  Future<void> setPrivacyEnabled(bool enabled) async {
    _isPrivacyEnabled = enabled;
    await _prefs.setBool('privacy_enabled', enabled);
    if (enabled) {
      await ScreenProtector.protectDataLeakageOn();
    } else {
      await ScreenProtector.protectDataLeakageOff();
    }
    notifyListeners();
  }

  Future<bool> authenticate() async {
    if (!_isBiometricEnabled) {
      _isAuthenticated = true;
      return true;
    }

    try {
      final bool canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      final bool canAuthenticate = canAuthenticateWithBiometrics || await _auth.isDeviceSupported();

      if (!canAuthenticate) {
        _isAuthenticated = true;
        return true;
      }

      final bool didAuthenticate = await _auth.authenticate(
        localizedReason: 'Please authenticate to access WealthFam',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
      
      _isAuthenticated = didAuthenticate;
      return didAuthenticate;
    } catch (e) {
      debugPrint("Auth Error: $e");
      return false;
    }
  }

  void logout() {
    _isAuthenticated = false;
    notifyListeners();
  }
}
