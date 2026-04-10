import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_app/core/theme/app_theme.dart';
import 'package:mobile_app/modules/auth/services/security_service.dart';

class BiometricGate extends StatefulWidget {
  final Widget child;
  const BiometricGate({super.key, required this.child});

  @override
  State<BiometricGate> createState() => _BiometricGateState();
}

class _BiometricGateState extends State<BiometricGate> {
  bool _isAuthenticating = false;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final security = context.read<SecurityService>();
    debugPrint("BiometricGate: isBiometricEnabled=${security.isBiometricEnabled}, isAuthenticated=${security.isAuthenticated}");
    if (security.isBiometricEnabled && !security.isAuthenticated) {
      _authenticate();
    }
  }

  Future<void> _authenticate() async {
    if (_isAuthenticating) return;
    debugPrint("BiometricGate: Requesting authentication...");
    setState(() => _isAuthenticating = true);
    
    final success = await context.read<SecurityService>().authenticate();
    debugPrint("BiometricGate: Authentication result: $success");
    
    if (mounted) {
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Authentication Failed'), backgroundColor: AppTheme.danger)
        );
      }
      setState(() => _isAuthenticating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SecurityService>(
      builder: (context, security, _) {
        if (!security.isBiometricEnabled || security.isAuthenticated) {
          return widget.child;
        }

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.fingerprint, size: 80, color: AppTheme.primary),
                const SizedBox(height: 24),
                const Text(
                  'Biometric Authentication',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  'WealthFam is locked for your security.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 48),
                ElevatedButton(
                  onPressed: _isAuthenticating ? null : _authenticate,
                  child: const Text('Unlock with Biometrics'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
