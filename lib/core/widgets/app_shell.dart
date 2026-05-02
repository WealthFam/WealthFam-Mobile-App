import 'package:flutter/material.dart';
import 'package:mobile_app/core/services/navigation_service.dart';
import 'package:mobile_app/core/theme/app_theme.dart';
import 'package:mobile_app/modules/auth/services/auth_service.dart';
import 'package:mobile_app/modules/config/screens/sync_settings_screen.dart';
import 'package:mobile_app/modules/home/screens/analytics_screen.dart';
import 'package:mobile_app/modules/home/screens/categories_management_screen.dart';
import 'package:mobile_app/modules/home/screens/expense_groups_screen.dart';
import 'package:mobile_app/modules/home/screens/goals_screen.dart';
import 'package:mobile_app/modules/home/screens/mutual_funds_screen.dart';
import 'package:mobile_app/modules/home/services/dashboard_service.dart';
import 'package:mobile_app/modules/ingestion/screens/sms_management_screen.dart';
import 'package:mobile_app/modules/vault/screens/vault_screen.dart';
import 'package:provider/provider.dart';

/// Key kept for HomeScreen compatibility.
final GlobalKey<ScaffoldState> appShellScaffoldKey = GlobalKey<ScaffoldState>();

/// Wraps the home screen body with the global drawer scaffold.
class AppShell extends StatelessWidget {

  const AppShell({
    required this.body, super.key,
    this.appBar,
    this.backgroundColor,
  });
  final Widget body;
  final PreferredSizeWidget? appBar;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      key: appShellScaffoldKey,
      backgroundColor: backgroundColor ?? theme.scaffoldBackgroundColor,
      appBar: appBar,
      drawer: const AppDrawer(),
      body: body,
    );
  }
}

/// Hamburger button that opens the NEAREST scaffold's drawer.
/// Each screen must have `drawer: const AppDrawer()` in its own Scaffold.
class DrawerMenuButton extends StatelessWidget {
  const DrawerMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (ctx) => IconButton(
        icon: const Icon(Icons.menu),
        tooltip: 'Menu',
        onPressed: () => Scaffold.of(ctx).openDrawer(),
      ),
    );
  }
}

/// Public reusable drawer widget.
/// Add `drawer: const AppDrawer()` to any Scaffold that needs navigation.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  void _navigate(BuildContext context, Widget screen, {int? tabIndex}) {
    Navigator.pop(context);
    if (tabIndex != null) {
      context.read<NavigationProvider>().setTab(tabIndex);
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => screen),
      );
    }
  }

  void _confirmSignOut(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text(
          'Are you sure you want to sign out from WealthFam?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
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
    final auth = context.read<AuthService>();
    final dashboard = context.watch<DashboardService>();
    final theme = Theme.of(context);

    Widget section(String label) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: theme.primaryColor,
          letterSpacing: 1.2,
        ),
      ),
    );

    Widget item(IconData icon, String label, Widget screen, {int? tabIndex}) =>
        ListTile(
          leading: Icon(icon),
          title: Text(label),
          onTap: () => _navigate(context, screen, tabIndex: tabIndex),
        );

    return Drawer(
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            margin: EdgeInsets.zero,
            accountName: Text(
              auth.userName ??
                  (auth.isApproved ? 'Wealth Management' : 'Pending Approval'),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.white,
                shadows: [
                  Shadow(
                    color: Colors.black26,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
            ),
            accountEmail: Text(
              '${auth.userRole ?? "Family Member"} • ${dashboard.data?.familyMembersCount != null ? "${dashboard.data!.familyMembersCount} Members" : "Family Account"}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            currentAccountPicture: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.5),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: CircleAvatar(
                backgroundColor: Colors.white,
                child: auth.userAvatar != null && auth.userAvatar!.length <= 2
                    ? Text(
                        auth.userAvatar!,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: theme.primaryColor,
                        ),
                      )
                    : Icon(
                        Icons.account_circle_outlined,
                        color: theme.primaryColor,
                        size: 40,
                      ),
              ),
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.primaryColor,
                  HSLColor.fromColor(theme.primaryColor)
                      .withHue(
                        (HSLColor.fromColor(theme.primaryColor).hue + 30) % 360,
                      )
                      .toColor(),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                section('Daily Activity'),
                ListTile(
                  leading: const Icon(Icons.dashboard_outlined),
                  title: const Text('Dashboard'),
                  onTap: () {
                    Navigator.pop(context);
                    context.read<NavigationProvider>().switchToDashboard();
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                ),
                item(
                  Icons.analytics_outlined,
                  'Insights & Analytics',
                  const AnalyticsScreen(),
                  tabIndex: 0,
                ),
                item(
                  Icons.message_outlined,
                  'SMS Management',
                  const SmsManagementScreen(),
                ),
                const Divider(height: 1),
                section('Wealth & Planning'),
                item(
                  Icons.trending_up,
                  'Mutual Funds',
                  const MutualFundsScreen(),
                  tabIndex: 2,
                ),
                item(
                  Icons.track_changes,
                  'Investment Goals',
                  const GoalsScreen(),
                ),
                item(
                  Icons.group_outlined,
                  'Expense Groups',
                  const ExpenseGroupsScreen(),
                ),
                const Divider(height: 1),
                section('Organisation'),
                item(
                  Icons.local_offer_outlined,
                  'Categories',
                  const CategoriesManagementScreen(),
                ),
                item(
                  Icons.folder_shared_outlined,
                  'Documents Vault',
                  const VaultScreen(),
                ),
                const Divider(height: 1),
                item(
                  Icons.settings_outlined,
                  'Settings',
                  const SyncSettingsScreen(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout, color: AppTheme.danger),
            title: const Text(
              'Sign Out',
              style: TextStyle(color: AppTheme.danger),
            ),
            onTap: () => _confirmSignOut(context),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
