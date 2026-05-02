import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:mobile_app/core/config/app_config.dart';
import 'package:mobile_app/core/theme/app_theme.dart';
import 'package:mobile_app/modules/auth/screens/login_screen.dart';
import 'package:mobile_app/modules/auth/services/auth_service.dart';
import 'package:mobile_app/modules/ingestion/services/sms_service.dart';
import 'package:mobile_app/modules/auth/services/security_service.dart';
import 'package:mobile_app/modules/auth/components/biometric_gate.dart';
import 'package:mobile_app/modules/home/screens/home_screen.dart';
import 'package:mobile_app/core/services/notification_service.dart';
import 'package:mobile_app/modules/home/services/dashboard_service.dart';
import 'package:mobile_app/modules/home/services/funds_service.dart';
import 'package:mobile_app/modules/home/services/categories_service.dart';
import 'package:mobile_app/modules/home/services/goals_service.dart';
import 'package:mobile_app/modules/vault/services/vault_service.dart';
import 'package:mobile_app/core/services/foreground_service.dart';
import 'package:mobile_app/core/services/socket_service.dart';
import 'package:mobile_app/core/utils/logger.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_app/core/services/navigation_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppLogger.minLevel = LogLevel.warning;

  if (!kIsWeb) {
    FlutterForegroundTask.initCommunicationPort();
  }

  final config = AppConfig();
  final auth = AuthService(config);
  final security = SecurityService();
  final sms = SmsService(config, auth);
  final notifications = NotificationService();

  try {
    await config.init().timeout(const Duration(seconds: 3));
    await auth.init().timeout(const Duration(seconds: 3));
    await security.init().timeout(const Duration(seconds: 3));
  } catch (e) {
    AppLogger.error('Core service initialization failed', e);
  }

  _initSecondaryServices(notifications);
  sms.init();

  final dashboard = DashboardService(config, auth);
  final funds = FundsService(config, auth);
  final categories = CategoriesService(config, auth);
  final vault = VaultService(config, auth);
  final goals = GoalsService(config, auth);
  final socket = SocketService(config, auth, notifications, dashboard);

  if (auth.isAuthenticated) {
    socket.connect();
    SharedPreferences.getInstance().then((prefs) {
      final isEnabled = prefs.getBool('fg_service_enabled') ?? false;
      if (isEnabled) {
        ForegroundServiceWrapper.start(
          url: config.backendUrl,
          token: auth.accessToken ?? '',
          deviceId: auth.deviceId,
        );
      }
    });
  }

  auth.addListener(() {
    if (auth.isAuthenticated) {
      if (!socket.isConnected) socket.connect();
    } else {
      socket.disconnect();
    }
  });

  if (!kIsWeb) {
    FlutterForegroundTask.addTaskDataCallback((data) {
      if (data is Map) {
        if (data['type'] == 'masking_update') {
          dashboard.updateMaskingFromForeground(data['value']);
        } else if (data['type'] == 'sms_synced') {
          sms.forceRefresh(data['hash']);
        }
      }
    });
  }

  runApp(
    MyApp(
      config: config,
      auth: auth,
      sms: sms,
      security: security,
      dashboard: dashboard,
      funds: funds,
      categories: categories,
      vault: vault,
      goals: goals,
      socket: socket,
      notifications: notifications,
    ),
  );
}

/// Start background services without blocking main app startup
Future<void> _initSecondaryServices(NotificationService notifications) async {
  try {
    await notifications.init().timeout(const Duration(seconds: 5));
    await ForegroundServiceWrapper.init().timeout(const Duration(seconds: 5));
  } catch (e) {
    AppLogger.warn('Secondary services initialization failed: $e');
  }
}

class MyApp extends StatelessWidget {
  final AppConfig config;
  final AuthService auth;
  final SmsService sms;
  final SecurityService security;
  final DashboardService dashboard;
  final FundsService funds;
  final CategoriesService categories;
  final VaultService vault;
  final GoalsService goals;
  final SocketService socket;
  final NotificationService notifications;

  const MyApp({
    super.key,
    required this.config,
    required this.auth,
    required this.sms,
    required this.security,
    required this.dashboard,
    required this.funds,
    required this.categories,
    required this.vault,
    required this.goals,
    required this.socket,
    required this.notifications,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: config),
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider.value(value: security),
        ChangeNotifierProvider.value(value: sms),
        ChangeNotifierProvider.value(value: dashboard),
        ChangeNotifierProvider.value(value: funds),
        ChangeNotifierProvider.value(value: categories),
        ChangeNotifierProvider.value(value: vault),
        ChangeNotifierProvider.value(value: goals),
        ChangeNotifierProvider.value(value: socket),
        ChangeNotifierProvider(create: (_) => NavigationProvider()),
        Provider.value(value: notifications),
      ],
      child: Consumer<AuthService>(
        builder: (context, auth, _) {
          return MaterialApp(
            key: ValueKey(auth.isAuthenticated),
            title: 'WealthFam',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            home: auth.isAuthenticated
                ? BiometricGate(child: const HomeScreen())
                : const LoginScreen(),
          );
        },
      ),
    );
  }
}
