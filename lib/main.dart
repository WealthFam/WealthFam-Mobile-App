import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:mobile_app/core/config/app_config.dart';
import 'package:mobile_app/core/services/foreground_service.dart';
import 'package:mobile_app/core/services/navigation_service.dart';
import 'package:mobile_app/core/services/notification_service.dart';
import 'package:mobile_app/core/services/socket_service.dart';
import 'package:mobile_app/core/services/theme_provider.dart';
import 'package:mobile_app/core/theme/app_theme.dart';
import 'package:mobile_app/core/utils/logger.dart';
import 'package:mobile_app/core/widgets/global_error_boundary.dart';
import 'package:mobile_app/modules/auth/components/biometric_gate.dart';
import 'package:mobile_app/modules/auth/screens/login_screen.dart';
import 'package:mobile_app/modules/auth/screens/onboarding_screen.dart';
import 'package:mobile_app/modules/auth/services/auth_service.dart';
import 'package:mobile_app/modules/auth/services/security_service.dart';
import 'package:mobile_app/modules/home/screens/home_screen.dart';
import 'package:mobile_app/modules/home/services/categories_service.dart';
import 'package:mobile_app/modules/home/services/dashboard_service.dart';
import 'package:mobile_app/modules/home/services/funds_service.dart';
import 'package:mobile_app/modules/home/services/goals_service.dart';
import 'package:mobile_app/modules/ingestion/services/sms_service.dart';
import 'package:mobile_app/modules/vault/services/vault_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppLogger.minLevel = LogLevel.warning;

  // Global Error Handling for Flutter Framework
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AppLogger.error('Flutter Framework Error', details.exception, details.stack);
  };

  // Global Error Handling for Async Errors
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.error('Global Async Error', error, stack);
    return true; // Mark as handled to prevent crash
  };

  if (!kIsWeb) {
    FlutterForegroundTask.initCommunicationPort();
  }

  final config = AppConfig();
  final auth = AuthService(config);
  final security = SecurityService();
  final sms = SmsService(config, auth);
  final notifications = NotificationService();
  final themeProvider = ThemeProvider();

  try {
    await config.init().timeout(const Duration(seconds: 3));
    await auth.init().timeout(const Duration(seconds: 3));
    await security.init().timeout(const Duration(seconds: 3));
    await themeProvider.init().timeout(const Duration(seconds: 3));
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
      if (data is Map<String, dynamic>) {
        if (data['type'] == 'masking_update') {
          final dynamic val = data['value'];
          if (val is num) {
            dashboard.updateMaskingFromForeground(val.toDouble());
          }
        } else if (data['type'] == 'sms_synced') {
          sms.forceRefresh(data['hash'] as String?);
        }
      }
    });
  }

  runApp(
    GlobalErrorBoundary(
      child: MyApp(
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
        themeProvider: themeProvider,
      ),
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

  const MyApp({
    required this.config, required this.auth, required this.sms, required this.security, required this.dashboard, required this.funds, required this.categories, required this.vault, required this.goals, required this.socket, required this.notifications, required this.themeProvider, super.key,
  });
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
  final ThemeProvider themeProvider;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: config),
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider.value(value: security),
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider.value(value: sms),
        ChangeNotifierProvider.value(value: dashboard),
        ChangeNotifierProvider.value(value: funds),
        ChangeNotifierProvider.value(value: categories),
        ChangeNotifierProvider.value(value: vault),
        ChangeNotifierProvider.value(value: goals),
        ChangeNotifierProvider.value(value: socket),
        ChangeNotifierProvider(create: (_) => NavigationProvider()),
        ChangeNotifierProvider.value(value: notifications),

      ],
      child: Consumer2<AuthService, ThemeProvider>(
        builder: (context, auth, theme, _) {
          return MaterialApp(
            key: ValueKey(auth.isAuthenticated),
            title: 'WealthFam',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: theme.themeMode,
            home: auth.isAuthenticated
                ? (auth.hasCompletedOnboarding
                    ? const BiometricGate(child: HomeScreen())
                    : const OnboardingScreen())
                : const LoginScreen(),
          );
        },
      ),
    );
  }
}

