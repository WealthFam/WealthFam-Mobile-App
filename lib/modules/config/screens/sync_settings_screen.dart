import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:mobile_app/core/config/app_config.dart';
import 'package:mobile_app/core/theme/app_theme.dart';
import 'package:mobile_app/modules/auth/services/auth_service.dart';
import 'package:mobile_app/modules/auth/services/security_service.dart';
import 'package:mobile_app/modules/ingestion/services/sms_service.dart';
import 'package:mobile_app/modules/ingestion/screens/sms_debug_logs_screen.dart';
import 'package:mobile_app/modules/home/services/dashboard_service.dart';
import 'package:mobile_app/core/widgets/app_shell.dart';

class SyncSettingsScreen extends StatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _backendCtrl;
  late TextEditingController _deviceIdCtrl;
  late TextEditingController _maskingCtrl;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final config = context.read<AppConfig>();
    final auth = context.read<AuthService>();
    if (!mounted) return;
    final dashboard = context.read<DashboardService>();
    _backendCtrl = TextEditingController(text: config.backendUrl);
    _deviceIdCtrl = TextEditingController(text: auth.deviceId ?? '');
    _maskingCtrl = TextEditingController(
      text: dashboard.maskingFactor.toString(),
    );
  }

  @override
  void dispose() {
    _backendCtrl.dispose();
    _deviceIdCtrl.dispose();
    _maskingCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    await context.read<AppConfig>().setUrls(
      backend: _backendCtrl.text.trim(),
      webUi: context.read<AppConfig>().webUiUrl,
    );

    if (!mounted) return;
    final authService = context.read<AuthService>();
    if (_deviceIdCtrl.text.isNotEmpty) {
      await authService.setDeviceId(_deviceIdCtrl.text.trim());
    }

    if (!mounted) return;
    final dashboardService = context.read<DashboardService>();
    final maskingFactor = double.tryParse(_maskingCtrl.text) ?? 1.0;
    await dashboardService.setMaskingFactor(maskingFactor);

    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configuration Saved'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text(
          'Are you sure you want to sign out? Your session will be cleared.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<AuthService>().logout();
            },
            child: const Text(
              'Sign Out',
              style: TextStyle(color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final config = context.watch<AppConfig>();
    final security = context.watch<SecurityService>();
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: const DrawerMenuButton(),
        title: const Text('Settings'),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(icon: const Icon(Icons.check), onPressed: _saveConfig),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle('ACCOUNT'),
              _buildAccountCard(auth),

              const SizedBox(height: 24),
              _buildSectionTitle('SERVER CONFIGURATION'),
              _buildServerCard(theme),

              const SizedBox(height: 24),
              _buildSectionTitle('SECURITY & PRIVACY'),
              _buildSecurityCard(
                security,
                config,
                context.watch<DashboardService>(),
              ),

              const SizedBox(height: 24),
              _buildSectionTitle('SMS & BACKGROUND SYNC'),
              _buildSmsSyncCard(context.watch<SmsService>()),

              const SizedBox(height: 24),
              _buildSectionTitle('DEVICE INFO'),
              _buildDeviceCard(theme),

              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: _confirmLogout,
                  icon: const Icon(Icons.logout, color: AppTheme.danger),
                  label: const Text(
                    'Sign Out from Device',
                    style: TextStyle(
                      color: AppTheme.danger,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: AppTheme.danger.withValues(alpha: 0.05),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  'Version 1.0.0 (BETA)',
                  style: TextStyle(color: theme.disabledColor, fontSize: 12),
                ),
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          color: Colors.grey,
        ),
      ),
    );
  }

  Widget _buildAccountCard(AuthService auth) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
              child: const Icon(Icons.person, color: AppTheme.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    auth.isApproved ? 'Approved Member' : 'Pending Approval',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    auth.userRole ?? 'Unknown Role',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            if (auth.isApproved)
              const Icon(Icons.verified, color: AppTheme.success, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildServerCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: TextFormField(
          controller: _backendCtrl,
          decoration: const InputDecoration(
            labelText: 'Backend URL',
            hintText: 'http://your-server-ip:8000',
            border: InputBorder.none,
            prefixIcon: Icon(Icons.dns_outlined, size: 20),
          ),
          validator: (v) => v!.isEmpty ? 'URL cannot be empty' : null,
        ),
      ),
    );
  }

  Widget _buildSecurityCard(
    SecurityService security,
    AppConfig config,
    DashboardService dashboard,
  ) {
    return Card(
      child: Column(
        children: [
          _buildSwitchTile(
            title: 'Biometric Lock',
            subtitle: 'Require FaceID/Fingerprint',
            value: security.isBiometricEnabled,
            onChanged: (v) => security.setBiometricEnabled(v),
            icon: Icons.fingerprint,
          ),
          const Divider(height: 1),
          _buildSwitchTile(
            title: 'Privacy Masking',
            subtitle: 'Hide dashboard in app switcher',
            value: security.isPrivacyEnabled,
            onChanged: (v) => security.setPrivacyEnabled(v),
            icon: Icons.visibility_off_outlined,
          ),
          const Divider(height: 1),
          _buildSwitchTile(
            title: 'Debug Mode',
            subtitle: 'Send detailed logs to server',
            value: config.sendDebugPayload,
            onChanged: (v) => config.setDebugPayload(v),
            icon: Icons.bug_report_outlined,
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(
                  Icons.calculate_outlined,
                  size: 20,
                  color: Colors.grey,
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Masking Factor',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Divide amounts to hide wealth',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 60,
                  child: TextFormField(
                    controller: _maskingCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmsSyncCard(SmsService smsService) {
    return Card(
      child: Column(
        children: [
          _buildSwitchTile(
            title: 'Auto-Sync Active',
            subtitle: 'Listening for financial SMS',
            value: smsService.isSyncEnabled,
            onChanged: (v) => smsService.toggleSync(v),
            icon: Icons.sync,
          ),
          const Divider(height: 1),
          _buildSwitchTile(
            title: 'Persistent Sync',
            subtitle: 'Recommended for background sync',
            value: smsService.isForegroundServiceEnabled,
            onChanged: (v) async {
              try {
                await smsService.toggleForegroundService(v);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        v
                            ? 'Background Sync Started'
                            : 'Background Sync Stopped',
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed: $e'),
                      backgroundColor: AppTheme.danger,
                    ),
                  );
                }
              }
            },
            icon: Icons.all_inclusive,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined, size: 20),
            title: const Text(
              'View Sync Logs',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            subtitle: const Text(
              'Debug incoming SMS payloads',
              style: TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.arrow_forward_ios, size: 14),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SmsDebugLogsScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: ListTile(
          title: const Text(
            'Device Identifier',
            style: TextStyle(fontSize: 14),
          ),
          subtitle: Text(
            _deviceIdCtrl.text,
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _deviceIdCtrl.text));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Copied ID')));
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
    required IconData icon,
  }) {
    return SwitchListTile(
      title: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
      ),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      secondary: Icon(icon, size: 20),
      value: value,
      onChanged: onChanged,
      activeThumbColor: AppTheme.primary,
    );
  }
}
