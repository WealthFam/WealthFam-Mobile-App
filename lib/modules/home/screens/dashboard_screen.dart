import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_app/modules/ingestion/services/sms_service.dart';
import 'package:intl/intl.dart';
import 'package:mobile_app/core/theme/app_theme.dart';
import 'package:mobile_app/modules/home/services/dashboard_service.dart';
import 'package:mobile_app/modules/auth/services/auth_service.dart';
import 'package:mobile_app/modules/home/models/dashboard_data.dart';
import 'package:mobile_app/modules/home/screens/analytics_screen.dart';
import 'package:mobile_app/modules/home/screens/mutual_funds_screen.dart';
import 'package:mobile_app/modules/ingestion/screens/transaction_review_screen.dart';
import 'package:mobile_app/modules/ingestion/screens/neural_training_screen.dart';
import 'package:mobile_app/modules/home/services/categories_service.dart';
import 'package:mobile_app/modules/home/models/transaction_category.dart';
import 'package:mobile_app/core/services/socket_service.dart';
import 'package:mobile_app/core/config/app_config.dart';
import 'package:mobile_app/modules/config/screens/sync_settings_screen.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:mobile_app/core/widgets/transaction_settings_sheet.dart';
import 'package:decimal/decimal.dart';
import 'package:mobile_app/modules/home/screens/add_transaction_screen.dart';
import 'package:mobile_app/modules/home/screens/calendar_heatmap_widget.dart';

class DashboardScreen extends StatefulWidget {
  final VoidCallback? onMenuPressed;
  const DashboardScreen({super.key, this.onMenuPressed});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Single call to load family overview data for current month
      context.read<DashboardService>().refresh();
      context.read<CategoriesService>().fetchCategories();
    });
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = context.watch<DashboardService>();
    final theme = Theme.of(context);
    final currencyFormat = NumberFormat.currency(
      symbol: dashboard.currencySymbol,
      decimalDigits: 0,
    );

    // Helper to format with masking
    String formatAmount(Decimal amount) {
      final numericAmount = amount.toDouble();
      return currencyFormat.format(numericAmount / dashboard.maskingFactor);
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: RefreshIndicator(
        onRefresh: () => dashboard.refresh(),
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              floating: true,
              pinned: false,
              leading: widget.onMenuPressed != null
                  ? IconButton(
                      icon: const Icon(Icons.menu),
                      onPressed: widget.onMenuPressed,
                    )
                  : null,
              title: GestureDetector(
                onDoubleTap: () {
                  dashboard.toggleMasking();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        dashboard.maskingFactor > 1.0
                            ? 'Privacy Masking ON (Panic Mode)'
                            : 'Privacy Masking OFF',
                      ),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Family Overview',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (dashboard.maskingFactor > 1.0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.warning.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: AppTheme.warning.withValues(alpha: 0.5),
                          ),
                        ),
                        child: const Text(
                          'PRIVACY',
                          style: TextStyle(
                            color: AppTheme.warning,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              bottom: null,
              actions: [
                Consumer<SocketService>(
                  builder: (context, socket, _) => Tooltip(
                    message: socket.isConnected
                        ? 'Real-time Connected'
                        : 'Real-time Disconnected',
                    child: Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: Icon(
                        socket.isConnected ? Icons.bolt : Icons.bolt_outlined,
                        color: socket.isConnected
                            ? AppTheme.success
                            : AppTheme.danger,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (dashboard.isLoading && dashboard.data == null)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (dashboard.data == null)
              SliverFillRemaining(
                child: _buildErrorPlaceholder(
                  context,
                  dashboard.error ?? 'No cached data available',
                ),
              )
            else ...[
              if (dashboard.error != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.danger.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        dashboard.error!,
                        style: const TextStyle(color: AppTheme.danger),
                      ),
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: _buildSummarySection(
                  context,
                  dashboard.data!.summary,
                  formatAmount,
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: () {
                    final year = dashboard.selectedYear ?? DateTime.now().year;
                    final month =
                        dashboard.selectedMonth ?? DateTime.now().month;
                    final lastDay = DateTime(year, month + 1, 0);
                    return CalendarHeatmapWidget(
                      data: dashboard.data!.calendarHeatmap,
                      maskingFactor: dashboard.maskingFactor,
                      endDate: lastDay,
                    );
                  }(),
                ),
              ),
              SliverToBoxAdapter(
                child: _buildInvestmentsEntry(
                  context,
                  dashboard.data!.investmentSummary,
                  formatAmount,
                ),
              ),
              if (dashboard.data!.pendingTriageCount > 0 ||
                  dashboard.data!.pendingTrainingCount > 0)
                SliverToBoxAdapter(
                  child: _buildTriageBanner(
                    context,
                    dashboard.data!.pendingTriageCount,
                    dashboard.data!.pendingTrainingCount,
                  ),
                ),
              SliverToBoxAdapter(
                child: _buildBudgetSection(
                  context,
                  dashboard.data!.budget,
                  formatAmount,
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Recent Transactions',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AnalyticsScreen(),
                            ),
                          );
                        },
                        child: const Text('See All'),
                      ),
                    ],
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final txn = dashboard.data!.recentTransactions[index];
                  return _buildTransactionItem(context, txn, formatAmount);
                }, childCount: dashboard.data!.recentTransactions.length),
              ),
              SliverToBoxAdapter(child: _buildSyncHealthCard(context)),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => AddTransactionScreen()),
          ).then((val) {
            if (val == true) dashboard.refresh();
          });
        },
        backgroundColor: AppTheme.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildSummarySection(
    BuildContext context,
    DashboardSummary summary,
    Function(Decimal) format,
  ) {
    // Trend for Today vs Yesterday
    final todayDiff = summary.todayTotal - summary.yesterdayTotal;
    final todayTrendIcon = todayDiff < Decimal.zero
        ? Icons.arrow_downward
        : (todayDiff > Decimal.zero ? Icons.arrow_upward : null);
    final todayTrendColor = todayDiff < Decimal.zero
        ? Colors.greenAccent
        : (todayDiff > Decimal.zero ? Colors.orangeAccent : Colors.white70);
    final todayTrendText = todayDiff != Decimal.zero
        ? '${todayDiff > Decimal.zero ? "+" : ""}${format(todayDiff.abs())}'
        : 'Same as yesterday';

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: _buildSummaryCard(
              context,
              'This Month',
              format(summary.monthlyTotal),
              [const Color(0xFF6366F1), const Color(0xFF4F46E5)],
              Icons.calendar_month,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AnalyticsScreen()),
                );
              },
              trend: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  Container(
                    height: 4,
                    width: 60,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor:
                          (summary.proratedBudget > Decimal.zero
                                  ? (summary.monthlyTotal.toDouble() /
                                        (summary.proratedBudget.toDouble() *
                                            1.5))
                                  : 0.0)
                              .clamp(0.0, 1.0)
                              .toDouble(),
                      child: Container(
                        decoration: BoxDecoration(
                          color: summary.monthlyTotal > summary.proratedBudget
                              ? Colors.orangeAccent
                              : Colors.greenAccent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Prorated Budget',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 8,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildSummaryCard(
              context,
              'Today',
              format(summary.todayTotal),
              [const Color(0xFF10B981), const Color(0xFF059669)],
              Icons.today,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AnalyticsScreen(showTodayOnly: true),
                  ),
                );
              },
              trend: Row(
                children: [
                  if (todayTrendIcon != null)
                    Icon(todayTrendIcon, size: 10, color: todayTrendColor),
                  const SizedBox(width: 2),
                  Text(
                    todayTrendText,
                    style: TextStyle(
                      color: todayTrendColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
    BuildContext context,
    String title,
    String amount,
    List<Color> colors,
    IconData icon, {
    VoidCallback? onTap,
    Widget? trend,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 170,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: colors.last.withValues(alpha: 0.4),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Background Ghost Icon
            Positioned(
              right: -10,
              bottom: -10,
              child: Icon(
                icon,
                color: Colors.white.withValues(alpha: 0.12),
                size: 80,
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: Colors.white, size: 18),
                ),
                const Spacer(),
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    amount,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                if (trend != null) ...[const SizedBox(height: 8), trend],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvestmentsEntry(
    BuildContext context,
    InvestmentSummary? summary,
    Function(Decimal) format,
  ) {
    if (context.read<AuthService>().userRole == 'CHILD') {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MutualFundsScreen()),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Sparkline on the left
              if (summary != null && summary.sparkline.isNotEmpty)
                Container(
                  width: 60,
                  height: 40,
                  margin: const EdgeInsets.only(right: 16),
                  child: LineChart(
                    LineChartData(
                      gridData: const FlGridData(show: false),
                      titlesData: const FlTitlesData(show: false),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: summary.sparkline
                              .asMap()
                              .entries
                              .map((e) => FlSpot(e.key.toDouble(), e.value))
                              .toList(),
                          isCurved: true,
                          color: summary.profitLoss >= Decimal.zero
                              ? Colors.greenAccent
                              : Colors.redAccent,
                          barWidth: 2,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(show: false),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(right: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.show_chart,
                    color: Colors.greenAccent,
                    size: 28,
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Mutual Funds Overview",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (summary != null &&
                        summary.currentValue > Decimal.zero) ...[
                      const SizedBox(height: 4),
                      // Current value + overall P&L
                      Row(
                        children: [
                          Text(
                            format(summary.currentValue),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "${summary.profitLoss >= Decimal.zero ? '+' : ''}${format(summary.profitLoss)}",
                            style: TextStyle(
                              color: summary.profitLoss >= Decimal.zero
                                  ? Colors.greenAccent
                                  : Colors.redAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (summary.totalInvested > Decimal.zero) ...[
                            const SizedBox(width: 4),
                            Text(
                              "(${((summary.profitLoss.toDouble() / summary.totalInvested.toDouble()) * 100).toStringAsFixed(1)}%)",
                              style: TextStyle(
                                color: summary.profitLoss >= Decimal.zero
                                    ? Colors.greenAccent.withValues(alpha: 0.8)
                                    : Colors.redAccent.withValues(alpha: 0.8),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      // Day change row
                      Row(
                        children: [
                          Icon(
                            summary.dayChange >= Decimal.zero
                                ? Icons.arrow_drop_up
                                : Icons.arrow_drop_down,
                            color: summary.dayChange >= Decimal.zero
                                ? Colors.greenAccent
                                : Colors.redAccent,
                            size: 14,
                          ),
                          Text(
                            "Today: ${summary.dayChange >= Decimal.zero ? '+' : ''}${format(summary.dayChange)} (${summary.dayChangePercent.toDouble().toStringAsFixed(2)}%)",
                            style: TextStyle(
                              color: summary.dayChange >= Decimal.zero
                                  ? Colors.greenAccent
                                  : Colors.redAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (summary.xirr != null &&
                              summary.xirr! > Decimal.zero) ...[
                            const SizedBox(width: 8),
                            Text(
                              "XIRR: ${summary.xirr!.toDouble().toStringAsFixed(1)}%",
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ] else
                      const Text(
                        "Track your portfolio performance",
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                color: Colors.white54,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBudgetSection(
    BuildContext context,
    BudgetSummary budget,
    Function(Decimal) format,
  ) {
    final theme = Theme.of(context);
    final isOver = budget.percentage > Decimal.parse('100');
    final color = isOver
        ? AppTheme.danger
        : (budget.percentage > Decimal.parse('80')
              ? AppTheme.warning
              : AppTheme.success);
    final summary = DashboardService.of(context).data?.summary;
    final prorated = summary?.proratedBudget ?? Decimal.zero;
    final isOverProrated = budget.spent > prorated && prorated > Decimal.zero;
    final healthLabel = isOverProrated ? 'Over Pace' : 'On Track';
    final healthColor = isOverProrated ? AppTheme.danger : AppTheme.success;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Family Budget',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Monthly Limit: ${format(budget.limit)}',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: healthColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  healthLabel,
                  style: TextStyle(
                    color: healthColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: LinearProgressIndicator(
                  value: (budget.percentage.toDouble() / 100.0).clamp(0.0, 1.0),
                  backgroundColor: theme.dividerColor.withValues(alpha: 0.1),
                  color: color.withValues(alpha: 0.3),
                  minHeight: 12,
                ),
              ),
              if (prorated > Decimal.zero && budget.limit > Decimal.zero)
                Positioned(
                  left:
                      (MediaQuery.of(context).size.width - 88) *
                      (prorated.toDouble() / budget.limit.toDouble()),
                  child: Container(
                    width: 2,
                    height: 12,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Spent: ${format(budget.spent)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              Text(
                'Pace: ${format(prorated)}',
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // _buildTopCategoriesSection and _buildAnalysisTabs removed as they have been moved to AnalyticsScreen

  Widget _buildTransactionItem(
    BuildContext context,
    RecentTransaction txn,
    Function(Decimal) format,
  ) {
    final theme = Theme.of(context);
    final isNegative = txn.amount < Decimal.zero;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: ListTile(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AnalyticsScreen()),
          );
        },
        onLongPress: () {
          TransactionSettingsSheet.show(context, txn);
        },
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Consumer<CategoriesService>(
          builder: (context, catService, _) {
            final localTheme = Theme.of(context);
            // Find category case-insensitive or exact
            // Find category case-insensitive or exact
            final catName = txn.category.contains(' › ')
                ? txn.category.split(' › ').last
                : txn.category;
            TransactionCategory? matched;

            for (var parent in catService.categories) {
              if (parent.name.toLowerCase() == catName.toLowerCase()) {
                matched = parent;
                break;
              }
              for (var sub in parent.subcategories) {
                if (sub.name.toLowerCase() == catName.toLowerCase()) {
                  matched = sub;
                  break;
                }
              }
              if (matched != null) break;
            }

            if (matched?.icon != null) {
              return CircleAvatar(
                backgroundColor: localTheme.primaryColor.withValues(alpha: 0.1),
                child: Text(
                  matched!.icon!,
                  style: const TextStyle(fontSize: 20),
                ),
              );
            }

            return CircleAvatar(
              backgroundColor: localTheme.primaryColor.withValues(alpha: 0.1),
              child: Text(
                (txn.accountOwnerName != null &&
                        txn.accountOwnerName!.isNotEmpty)
                    ? txn.accountOwnerName![0].toUpperCase()
                    : (txn.category.isNotEmpty
                          ? txn.category[0].toUpperCase()
                          : '?'),
                style: TextStyle(
                  color: localTheme.primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            );
          },
        ),
        title: Text(
          txn.description,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${txn.source ?? txn.category} • ${txn.accountName ?? 'Account'} • ${txn.formattedDate}',
              style: TextStyle(
                fontSize: 10,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (txn.expenseGroupName != null) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.folder_shared_outlined,
                      size: 8,
                      color: AppTheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      txn.expenseGroupName!,
                      style: const TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        trailing: Text(
          format(txn.amount),
          style: TextStyle(
            color: isNegative ? AppTheme.danger : AppTheme.success,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  Widget _buildTriageBanner(
    BuildContext context,
    int triageCount,
    int trainingCount,
  ) {
    if (triageCount == 0 && trainingCount == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        children: [
          if (triageCount > 0)
            _buildActionBanner(
              context,
              title: 'Review $triageCount Transactions',
              subtitle: 'Verify low-confidence items',
              icon: Icons.fact_check_outlined,
              color: AppTheme.warning,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const TransactionReviewScreen(),
                ),
              ),
            ),
          if (triageCount > 0 && trainingCount > 0) const SizedBox(height: 12),
          if (trainingCount > 0)
            _buildActionBanner(
              context,
              title: '$trainingCount Training Items',
              subtitle: 'Teach the system new patterns',
              icon: Icons.auto_awesome,
              color: AppTheme.primary,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NeuralTrainingScreen()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionBanner(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 12,
              color: color.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncHealthCard(BuildContext context) {
    final sms = context.watch<SmsService>();
    final theme = Theme.of(context);
    final lastSyncStr = sms.lastSyncTime != null
        ? DateFormat('HH:mm').format(sms.lastSyncTime!)
        : 'Never';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.sync_problem_outlined,
                size: 18,
                color: sms.queueCount > 0
                    ? AppTheme.warning
                    : theme.primaryColor,
              ),
              const SizedBox(width: 8),
              Text(
                sms.queueCount > 0 ? 'Action Required' : 'Sync Health',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              if (sms.isSyncing)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.primary,
                  ),
                )
              else
                Text(
                  sms.lastSyncStatus ?? 'Healthy',
                  style: TextStyle(
                    color:
                        (sms.lastSyncStatus == 'Success' ||
                            sms.lastSyncStatus == null)
                        ? AppTheme.success
                        : (sms.lastSyncStatus == 'Failed'
                              ? AppTheme.danger
                              : AppTheme.warning),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildHealthStat(context, 'Last Sync', lastSyncStr),
              _buildHealthStat(
                context,
                'Today',
                sms.messagesSyncedToday.toString(),
              ),
              _buildHealthStat(
                context,
                'Unsynced',
                sms.queueCount.toString(),
                isWarning: sms.queueCount > 0,
                onTap: () => _showUnsyncedMessagesSheet(context),
              ),
            ],
          ),
          const Divider(height: 32),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sms.queueCount > 0
                          ? 'Messages pending sync'
                          : 'All messages are up to date',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (sms.queueCount > 0)
                      const Text(
                        'Tap Sync Now to push items manually',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppTheme.warning,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: sms.isSyncing ? null : () => sms.syncNow(),
                style: TextButton.styleFrom(
                  backgroundColor: theme.primaryColor.withValues(alpha: 0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
                icon: sms.isSyncing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync, size: 16),
                label: Text(
                  sms.isSyncing ? 'Syncing...' : 'Sync Now',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHealthStat(
    BuildContext context,
    String label,
    String value, {
    bool isWarning = false,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: isWarning
                    ? AppTheme.warning
                    : theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showUnsyncedMessagesSheet(BuildContext context) {
    final sms = context.read<SmsService>();
    final items = sms.getQueueItems();
    final theme = Theme.of(context);

    if (items.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No messages pending sync')));
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.sync_problem,
                      color: AppTheme.warning,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${items.length} Unsynced Messages',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Text(
                          'Cached locally due to connection issues',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                itemCount: items.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final date = DateTime.fromMillisecondsSinceEpoch(
                    item['date'] ?? 0,
                  );
                  final timeStr = DateFormat('dd MMM, HH:mm').format(date);

                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              item['address'] ?? 'Unknown',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              timeStr,
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item['body'] ?? '',
                          style: const TextStyle(fontSize: 13),
                        ),
                        if (item['latitude'] != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on,
                                size: 10,
                                color: AppTheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${item['latitude'].toStringAsFixed(6)}, ${item['longitude'].toStringAsFixed(6)}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: theme.primaryColor,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    sms.retryQueue();
                  },
                  icon: const Icon(Icons.cloud_upload),
                  label: const Text(
                    'Sync All Now',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorPlaceholder(BuildContext context, String error) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 80,
              color: theme.colorScheme.error.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'Server Unreachable',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'We couldn'
              't connect to the backend at ${context.read<AppConfig>().backendUrl}. Please check your connection or server settings.',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => SyncSettingsScreen()));
              },
              icon: const Icon(Icons.settings),
              label: const Text('Update Server URL'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
            TextButton(
              onPressed: () => context.read<DashboardService>().refresh(),
              child: const Text('Retry Connection'),
            ),
          ],
        ),
      ),
    );
  }
}
