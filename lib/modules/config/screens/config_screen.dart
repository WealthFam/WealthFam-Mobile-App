import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_app/core/config/app_config.dart';
import 'package:mobile_app/core/theme/app_theme.dart';
import 'package:mobile_app/modules/auth/services/auth_service.dart';

class ConfigScreen extends StatefulWidget {
  final VoidCallback? onSaved;
  
  const ConfigScreen({super.key, this.onSaved});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _backendCtrl;
  late TextEditingController _deviceIdCtrl;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final config = context.read<AppConfig>();
    final auth = context.read<AuthService>();
    _backendCtrl = TextEditingController(text: config.backendUrl);
    _deviceIdCtrl = TextEditingController(text: auth.deviceId ?? '');
  }

  @override
  void dispose() {
    _backendCtrl.dispose();
    _deviceIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);
    
    await context.read<AppConfig>().setUrls(
      backend: _backendCtrl.text.trim(),
      webUi: context.read<AppConfig>().webUiUrl,
    );

    if (_deviceIdCtrl.text.isNotEmpty) {
      await context.read<AuthService>().setDeviceId(_deviceIdCtrl.text.trim());
    }
    
    await Future.delayed(const Duration(milliseconds: 500));
    
    if (mounted) setState(() => _isLoading = false);
    
    if (widget.onSaved != null) {
      widget.onSaved!();
    } else {
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuration Saved'), duration: Duration(seconds: 1)),
        );
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Server Configuration'),
        backgroundColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
               const Icon(
                Icons.settings_ethernet,
                size: 64,
                color: AppTheme.primary,
              ),
              const SizedBox(height: 32),
              
              Text(
                'Connect to WealthFam',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface
                ),
                textAlign: TextAlign.center,
              ),
               const SizedBox(height: 8),
              Text(
                'Configure your self-hosted server endpoints.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),

              TextFormField(
                controller: _backendCtrl,
                style: TextStyle(color: theme.colorScheme.onSurface),
                decoration: const InputDecoration(
                  labelText: 'Backend API URL',
                  hintText: 'http://192.168.0.9:8000',
                  prefixIcon: Icon(Icons.api),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Required';
                  if (!value.startsWith('http')) return 'Must start with http/https';
                  return null;
                },
              ),
              const SizedBox(height: 24),

              const SizedBox(height: 24),

              TextFormField(
                controller: _deviceIdCtrl,
                style: TextStyle(color: theme.colorScheme.onSurface),
                decoration: InputDecoration(
                  labelText: 'Device ID',
                  hintText: 'Unique Device Identifier',
                  prefixIcon: const Icon(Icons.perm_device_information),
                  helperText: 'Changing this will require re-approval.',
                  helperStyle: const TextStyle(color: AppTheme.warning),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Required';
                  return null;
                },
              ),
              
              const SizedBox(height: 48),
              
              ElevatedButton(
                onPressed: _isLoading ? null : _save,
                child: _isLoading 
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                  : const Text('Save Configuration'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
