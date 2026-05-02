import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:mobile_app/core/config/app_config.dart';
import 'package:mobile_app/core/theme/app_theme.dart';
import 'package:mobile_app/core/widgets/app_shell.dart';
import 'package:mobile_app/core/widgets/transaction_settings_sheet.dart';
import 'package:mobile_app/modules/auth/services/auth_service.dart';
import 'package:mobile_app/modules/home/models/dashboard_data.dart';
import 'package:mobile_app/modules/home/models/transaction_category.dart';
import 'package:mobile_app/modules/home/screens/add_transaction_screen.dart';
import 'package:mobile_app/modules/home/screens/calendar_heatmap_widget.dart';
import 'package:mobile_app/modules/home/screens/spending_heatmap_widget.dart';
import 'package:mobile_app/modules/home/screens/transaction_detail_screen.dart';
import 'package:mobile_app/modules/home/services/categories_service.dart';
import 'package:mobile_app/modules/home/services/dashboard_service.dart';
import 'package:mobile_app/modules/home/widgets/analytics_charts.dart';
import 'package:mobile_app/modules/vault/screens/vault_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key, this.showTodayOnly = false});
  final bool showTodayOnly;

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final List<dynamic> _transactions = [];
  bool _isTxnLoading = false;
  bool _hasMore = true;
  int _page = 1;
  final ScrollController _scrollController = ScrollController();
  DashboardService? _dashboard;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dashboard = context.read<DashboardService>();
      _dashboard?.addListener(_onFiltersChanged);

      // Load cache and trigger refresh
      _loadTransactionCache();
      _dashboard?.refresh();
      context.read<CategoriesService>().fetchCategories();
    });

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        _fetchTransactions();
      }
    });
  }

  @override
  void dispose() {
    _dashboard?.removeListener(_onFiltersChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onFiltersChanged() {
    if (!context.mounted) return;

    // Always clear the view and start fresh when filters change
    // This prevents "stale month" impression even if a previous load was in-flight
    _loadTransactionCache(); // This will clear the list and load cache for the NEW month
    _fetchTransactions(reset: true);
  }

  String get _cacheKey {
    final d = _dashboard;
    if (d == null) return 'txn_cache_default';
    return 'txn_cache_${d.selectedYear}_${d.selectedMonth}_${d.selectedMemberId ?? "all"}';
  }

  Future<void> _loadTransactionCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cacheKey);
      if (cached != null && mounted) {
        setState(() {
          _transactions.clear();
          final decoded = jsonDecode(cached) as List<dynamic>;
          _transactions.addAll(decoded);
          _hasMore = true; // Assume there's more until we fetch
        });
      }
    } catch (e) {
      debugPrint('Error loading txn cache: $e');
    }
  }

  Future<void> _saveTransactionCache() async {
    try {
      if (_transactions.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        // Only cache the first page (20 txns) for fast loading
        final toCache = _transactions.take(20).toList();
        await prefs.setString(_cacheKey, jsonEncode(toCache));
      }
    } catch (e) {
      debugPrint('Error saving txn cache: $e');
    }
  }

  Future<void> _fetchTransactions({bool reset = false}) async {
    if (_isTxnLoading || (!reset && !_hasMore)) return;
    if (reset) {
      setState(() {
        _page = 1;
        _hasMore = true;
      });
    }
    setState(() => _isTxnLoading = true);

    final config = context.read<AppConfig>();
    final auth = context.read<AuthService>();
    final dashboard = context.read<DashboardService>();

    final url = Uri.parse('${config.backendUrl}/api/v1/mobile/transactions')
        .replace(
          queryParameters: {
            'page': _page.toString(),
            'page_size': '20',
            if (dashboard.selectedMonth != null)
              'month':
                  (widget.showTodayOnly
                          ? DateTime.now().month
                          : dashboard.selectedMonth)
                      .toString(),
            if (dashboard.selectedYear != null)
              'year':
                  (widget.showTodayOnly
                          ? DateTime.now().year
                          : dashboard.selectedYear)
                      .toString(),
            if (widget.showTodayOnly) 'day': DateTime.now().day.toString(),
            if (dashboard.selectedMemberId != null)
              'member_id': dashboard.selectedMemberId,
          },
        );

    try {
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer ${auth.accessToken}'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final items = data['data'] as List<dynamic>? ?? [];
        final dynamic nextPage = data['next_page'];

        if (mounted) {
          setState(() {
            if (reset) _transactions.clear();
            _transactions.addAll(
              items.where((i) {
                final item = i as Map<String, dynamic>;
                return item['is_hidden'] != true;
              }),
            );
            _hasMore = nextPage != null;
            _page++;
          });
          _saveTransactionCache();
        }
      }
    } catch (e) {
      debugPrint('Error fetching analytics transactions: $e');
    } finally {
      if (mounted) {
        setState(() => _isTxnLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = context.watch<DashboardService>();
    final theme = Theme.of(context);
    final currencyFormat = NumberFormat.currency(
      symbol: dashboard.currencySymbol,
      decimalDigits: 0,
    );

    String formatAmount(Decimal amount) {
      return currencyFormat.format(amount.toDouble() / dashboard.maskingFactor);
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: const DrawerMenuButton(),
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: const Text(
          'Insights',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (dashboard.members.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.people_outline),
              tooltip: 'Filter by member',
              initialValue: dashboard.selectedMemberId,
              onSelected: (val) {
                dashboard.setMember(val == 'all' ? null : val);
              },
              itemBuilder: (context) => <PopupMenuEntry<String>>[
                const PopupMenuItem(
                  value: 'all',
                  child: Text('👩‍👩‍👧‍👦 Full Family'),
                ),
                const PopupMenuDivider(),
                ...dashboard.members.map(
                  (mRaw) {
                    final m = mRaw as Map<String, dynamic>;
                    return PopupMenuItem(
                      value: m['id'].toString(),
                      child: Text(
                        '${m['role'] == "CHILD" ? "👶" : "👤"} ${m['name']}',
                      ),
                    );
                  },
                ),
              ],
            ),
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: 'Select Month',
            onPressed: () => _showMonthPicker(context),
          ),
        ],
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: () async {
              await dashboard.refresh();
              await _fetchTransactions(reset: true);
            },
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _buildFilterSummary(context, dashboard),
                  ),
                ),
                if (dashboard.data != null) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildPremiumHeader(context, dashboard, formatAmount),
                          const SizedBox(height: 12),
                          SmartInsightWidget(data: dashboard.data!),
                          const SizedBox(height: 24),
                          _buildSectionTitle(context, 'Spending Trend'),
                          const SizedBox(height: 12),
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0.0, end: 1.0),
                            duration: const Duration(milliseconds: 600),
                            curve: Curves.easeOutCubic,
                            builder: (context, value, child) {
                              return Opacity(
                                opacity: value,
                                child: Transform.translate(
                                  offset: Offset(0, 20 * (1 - value)),
                                  child: child,
                                ),
                              );
                            },
                            child: MonthTrendChart(
                              trend: dashboard.data!.monthWiseTrend,
                              maskingFactor: dashboard.maskingFactor,
                            ),
                          ),
                          const SizedBox(height: 32),
                          _buildSectionTitle(
                            context,
                            'Fiscal Pulse (Annual Heatmap)',
                          ),
                          const SizedBox(height: 12),
                          () {
                            final year =
                                dashboard.selectedYear ?? DateTime.now().year;
                            final month =
                                dashboard.selectedMonth ?? DateTime.now().month;
                            final lastDay = DateTime(
                              year,
                              month + 1,
                              0,
                              23,
                              59,
                              59,
                            );
                            final firstDay = lastDay.subtract(
                              const Duration(days: 364),
                            );
                            return CalendarHeatmapWidget(
                              data: dashboard.data!.calendarHeatmap,
                              maskingFactor: dashboard.maskingFactor,
                              startDate: firstDay,
                              endDate: lastDay,
                            );
                          }(),
                          const SizedBox(height: 32),
                          _buildSectionTitle(context, 'Geographical Spending'),
                          const SizedBox(height: 12),
                          const SpendingHeatmapWidget(),
                          const SizedBox(height: 32),
                          _buildSectionTitle(
                            context,
                            'Daily Activity (This Month)',
                          ),
                          const SizedBox(height: 12),
                          DailyTrendLineChart(
                            trend: dashboard.data!.spendingTrend,
                            maskingFactor: dashboard.maskingFactor,
                          ),
                          const SizedBox(height: 32),
                          _buildSectionTitle(context, 'Category Breakdown'),
                          const SizedBox(height: 12),
                          CategorySpendingPieChart(
                            distribution: dashboard.data!.categoryDistribution,
                            formatAmount: formatAmount,
                          ),
                          const SizedBox(height: 32),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildSectionTitle(context, 'Detailed Ledger'),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withValues(
                                    alpha: 0.1,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  'Total: ${formatAmount(dashboard.data!.summary.monthlyTotal)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),
                  if (_transactions.isNotEmpty)
                    _buildTransactionSliverList(context)
                  else if (!(_isTxnLoading && _transactions.isEmpty))
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Text(
                            'No transactions found for this period',
                            style: TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                        ),
                      ),
                    ),
                ] else if (dashboard.isLoading ||
                    (_isTxnLoading && _transactions.isEmpty)) ...[
                  const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ] else ...[
                  const SliverFillRemaining(
                    child: Center(
                      child: Text('No transactions found for this period'),
                    ),
                  ),
                ],
                if (_isTxnLoading && _transactions.isNotEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 48)),
              ],
            ),
          ),
          if ((dashboard.isLoading || _isTxnLoading) && _transactions.isEmpty)
            Positioned.fill(
              child: Container(
                color: theme.scaffoldBackgroundColor.withValues(alpha: 0.3),
                child: const Center(
                  child: Card(
                    elevation: 4,
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text(
                            'Fetching latest data...',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _buildFab(context),
    );
  }

  Widget _buildFilterSummary(BuildContext context, DashboardService dashboard) {
    final theme = Theme.of(context);
    String memberName = 'Full Family';
    if (dashboard.selectedMemberId != null) {
      final member = dashboard.members.firstWhere(
        (mRaw) {
          final m = mRaw as Map<String, dynamic>;
          return m['id'].toString() == dashboard.selectedMemberId;
        },
        orElse: () => null,
      ) as Map<String, dynamic>?;
      if (member != null) memberName = member['name'] as String? ?? 'Member';
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        spacing: 8,
        children: [
          Chip(
            label: Text(
              DateFormat('MMMM yyyy').format(
                DateTime(
                  dashboard.selectedYear ?? 2024,
                  dashboard.selectedMonth ?? 1,
                ),
              ),
            ),
            labelStyle: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
            backgroundColor: theme.primaryColor.withValues(alpha: 0.1),
            side: BorderSide.none,
            avatar: Icon(
              Icons.calendar_today,
              size: 12,
              color: theme.primaryColor,
            ),
          ),
          Chip(
            label: Text(memberName),
            labelStyle: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
            backgroundColor: theme.primaryColor.withValues(alpha: 0.1),
            side: BorderSide.none,
            avatar: Icon(
              Icons.person_outline,
              size: 12,
              color: theme.primaryColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
      ),
    );
  }

  Widget _buildPremiumHeader(
    BuildContext context,
    DashboardService dashboard,
    String Function(Decimal) format,
  ) {
    if (dashboard.data == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final data = dashboard.data!;
    final summary = data.summary;

    // Status color for today vs daily budget

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildGlassCard(
                context,
                'Monthly Spend',
                format(summary.monthlyTotal),
                Icons.account_balance_wallet_rounded,
                theme.colorScheme.primary,
                subtitle: 'vs ${format(data.budget.limit)} limit',
                progress: data.budget.limit > Decimal.zero
                    ? (summary.monthlyTotal.toDouble() /
                          data.budget.limit.toDouble())
                    : 0.0,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildGlassCard(
                context,
                'Budget Used',
                '${data.budget.percentage.toDouble().toStringAsFixed(1)}%',
                Icons.speed_rounded,
                data.budget.percentage > Decimal.parse('100')
                    ? AppTheme.danger
                    : (data.budget.percentage > Decimal.parse('90')
                          ? AppTheme.warning
                          : AppTheme.success),
                subtitle: data.budget.percentage > Decimal.parse('100')
                    ? 'Over Limit!'
                    : 'On Track',
                progress: data.budget.percentage.toDouble() / 100.0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (summary.todayTotal > Decimal.zero ||
            summary.dailyBudgetLimit > Decimal.zero)
          _buildDailyHealthCard(context, summary, dashboard.maskingFactor),
      ],
    );
  }

  Widget _buildDailyHealthCard(
    BuildContext context,
    DashboardSummary summary,
    double maskingFactor,
  ) {
    final theme = Theme.of(context);
    final isOverDaily = summary.todayTotal > summary.dailyBudgetLimit;
    final currency =
        context.read<DashboardService>().data?.summary.currency ?? '₹';
    final healthColor = isOverDaily ? AppTheme.danger : AppTheme.success;

    final yesterdayDiff = summary.todayTotal - summary.yesterdayTotal;
    final lastMonthDiff = summary.todayTotal - summary.lastMonthSameDayTotal;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: healthColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: healthColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.today, size: 14, color: healthColor),
                      const SizedBox(width: 6),
                      const Text(
                        'Today\'s Consumption',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '$currency${NumberFormat.decimalPattern().format(summary.todayTotal.toDouble() / maskingFactor)}',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'Daily Limit',
                    style: TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                  Text(
                    '$currency${NumberFormat.compact().format(summary.dailyBudgetLimit.toDouble() / maskingFactor)}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: healthColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isOverDaily ? 'LIMIT EXCEEDED' : 'WITHIN BUDGET',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: healthColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1),
          ),
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _buildTrendItem(
                    context,
                    'vs Yesterday',
                    yesterdayDiff,
                    maskingFactor,
                  ),
                ),
                VerticalDivider(
                  width: 32,
                  thickness: 1,
                  color: theme.dividerColor.withValues(alpha: 0.3),
                ),
                Expanded(
                  child: _buildTrendItem(
                    context,
                    'vs Last Month Same Day',
                    lastMonthDiff,
                    maskingFactor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendItem(
    BuildContext context,
    String label,
    Decimal diff,
    double maskingFactor) {
    final isNegative = diff < Decimal.zero;
    final color = isNegative
        ? AppTheme.success
        : (diff == Decimal.zero ? Colors.grey : AppTheme.danger);
    final icon = isNegative
        ? Icons.trending_down
        : (diff == Decimal.zero ? Icons.trending_flat : Icons.trending_up);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            color: Colors.grey,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              '${diff > Decimal.zero ? "+" : ""}${NumberFormat.compact().format(diff.toDouble() / maskingFactor)}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGlassCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color, {
    String? subtitle,
    double? progress,
  }) {
    final theme = Theme.of(context);
    return Container(
      height: 110,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.08),
            color.withValues(alpha: 0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 9,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                title,
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          if (progress != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                backgroundColor: color.withValues(alpha: 0.1),
                color: color,
                minHeight: 3,
              ),
            ),
        ],
      ),
    );
  }


  void _showMonthPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          height: 400,
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(24.0),
                child: Text(
                  'Analyse Period',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: 12,
                  itemBuilder: (context, index) {
                    final monthDate = DateTime(
                      DateTime.now().year,
                      DateTime.now().month - index,
                    );
                    final isSelected =
                        _dashboard?.selectedMonth == monthDate.month &&
                        _dashboard?.selectedYear == monthDate.year;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Theme.of(
                                context,
                              ).primaryColor.withValues(alpha: 0.1)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ListTile(
                        leading: Icon(
                          Icons.circle,
                          size: 12,
                          color: isSelected
                              ? Theme.of(context).primaryColor
                              : Colors.grey[300],
                        ),
                        title: Text(
                          DateFormat('MMMM yyyy').format(monthDate),
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected
                                ? Theme.of(context).primaryColor
                                : null,
                          ),
                        ),
                        trailing: isSelected
                            ? Icon(
                                Icons.check_circle,
                                color: Theme.of(context).primaryColor,
                              )
                            : null,
                        onTap: () {
                          _dashboard?.setMonth(monthDate.month, monthDate.year);
                          Navigator.pop(context);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTransactionSliverList(BuildContext context) {
    if (_transactions.isEmpty && !_isTxnLoading) {
      return SliverToBoxAdapter(
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(48),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
            ),
          ),
          child: const Column(
            children: [
              Icon(Icons.layers_clear_outlined, size: 48, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'Clear ledger for this period',
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Grouping by date
    final Map<String, List<dynamic>> grouped = {};
    for (var txnRaw in _transactions) {
      final txn = txnRaw as Map<String, dynamic>;
      final date = DateTime.parse(txn['date'] as String).toLocal();
      final key = DateFormat('yyyy-MM-dd').format(date);
      grouped.putIfAbsent(key, () => []).add(txn);
    }

    final keys = grouped.keys.toList();

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final dateKey = keys[index];
        final dateTxns = grouped[dateKey]!;
        final displayDate = DateFormat(
          'EEEE, MMM d',
        ).format(DateTime.parse(dateKey));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Text(
                displayDate.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).disabledColor,
                  letterSpacing: 1,
                ),
              ),
            ),
            ...dateTxns.map((txn) => _buildTransactionItem(context, txn)),
          ],
        );
      }, childCount: keys.length),
    );
  }

  Widget _buildTransactionItem(BuildContext context, dynamic txnRaw) {
    final txn = txnRaw as Map<String, dynamic>;
    final theme = Theme.of(context);
    final dashboard = context.read<DashboardService>();
    final amount = (txn['amount'] as num).toDouble();
    final date = DateTime.parse(txn['date'] as String).toLocal();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => TransactionDetailScreen(
                transaction: RecentTransaction.fromJson(txn),
              ),
            ),
          );
        },
        onLongPress: () {
          TransactionSettingsSheet.show(
            context,
            RecentTransaction.fromJson(txn),
          );
        },

        leading: Consumer<CategoriesService>(
          builder: (context, catService, _) {
            final catNameRaw = txn['category'] as String? ?? 'Uncategorized';
            final catName =
                catNameRaw.contains(' › ')
                    ? catNameRaw.split(' › ').last
                    : catNameRaw;
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

            return Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: theme.primaryColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Text(
                matched?.icon ??
                    (catName.isNotEmpty ? catName[0].toUpperCase() : '?'),
                style: TextStyle(
                  fontSize: 20,
                  color: theme.primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            );
          },
        ),
        title: Text(
          txn['description'] as String? ?? 'No Description',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
        subtitle: Text(
          '${DateFormat('h:mm a').format(date)} • ${txn['account_name'] ?? 'Account'}',
          style: TextStyle(
            fontSize: 11,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            fontWeight: FontWeight.w500,
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              NumberFormat.simpleCurrency(
                name: 'INR',
                decimalDigits: 0,
              ).format(amount / dashboard.maskingFactor),
              style: TextStyle(
                color: amount < 0 ? AppTheme.danger : AppTheme.success,
                fontWeight: FontWeight.w900,
                fontSize: 14,
                letterSpacing: -0.5,
              ),
            ),
            if (txn['has_documents'] == true)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: GestureDetector(
                  onTap: () {
                    // Navigate to Vault with search pre-filled
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => VaultScreen(
                          initialSearch: txn['description'] as String?,
                        ),
                      ),
                    );
                  },
                  child: Icon(
                    Icons.attach_file,
                    size: 16,
                    color: theme.primaryColor,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }


  Widget _buildFab(BuildContext context) {
    return FloatingActionButton(
      onPressed: () {
        Navigator.push<bool>(
          context,
          MaterialPageRoute<bool>(builder: (_) => const AddTransactionScreen()),
        ).then((val) {
          if (val == true && context.mounted) {
            context.read<DashboardService>().refresh();
            _fetchTransactions(reset: true);
          }
        });
      },
      backgroundColor: AppTheme.primary,
      child: const Icon(Icons.add, color: Colors.white),
    );
  }
}
