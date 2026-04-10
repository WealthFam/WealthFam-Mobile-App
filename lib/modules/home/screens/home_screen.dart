import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:mobile_app/modules/home/screens/dashboard_screen.dart';
import 'package:mobile_app/core/theme/app_theme.dart';
import 'package:mobile_app/modules/auth/services/auth_service.dart';
import 'package:mobile_app/modules/ingestion/services/sms_service.dart';
import 'package:mobile_app/core/widgets/app_shell.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SmsService>().syncUnsyncedOnStart();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final shell = WithForegroundTask(
      child: AppShell(
        body: SafeArea(
          child: DashboardScreen(
            onMenuPressed: () => appShellScaffoldKey.currentState?.openDrawer(),
          ),
        ),
      ),
    );

    if (kIsWeb) {
      return Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 450),
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            border: Border.symmetric(vertical: BorderSide(color: theme.dividerColor, width: 1)),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 10))
            ],
          ),
          child: shell,
        ),
      );
    }

    return shell;
  }
}

