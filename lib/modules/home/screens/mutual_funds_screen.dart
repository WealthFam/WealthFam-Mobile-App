import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:mobile_app/core/theme/app_theme.dart';
import 'package:mobile_app/modules/home/services/funds_service.dart';
import 'package:mobile_app/modules/home/services/dashboard_service.dart';
import 'package:mobile_app/modules/home/models/fund_models.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:mobile_app/core/widgets/app_shell.dart';
import 'package:decimal/decimal.dart';
import 'dart:math' as math;

class MutualFundsScreen extends StatefulWidget {
  const MutualFundsScreen({super.key});

  @override
  State<MutualFundsScreen> createState() => _MutualFundsScreenState();
}

class _MutualFundsScreenState extends State<MutualFundsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Sync member selection from dashboard if needed, or just default to null (All)
      // For now, start fresh or use local state.
      // Let's assume independent filter for this screen.
      context.read<FundsService>().fetchFunds();
    });
  }

  @override
  Widget build(BuildContext context) {
    final fundsService = context.watch<FundsService>();
    final dashboardService = context
        .watch<DashboardService>(); // reusing members list & masking
    final theme = Theme.of(context);

    // Masking Helper
    final currencyFormat = NumberFormat.currency(
      symbol: dashboardService.currencySymbol,
      decimalDigits: 0,
    );
    String formatAmount(Decimal amount) {
      return currencyFormat.format(
        amount.toDouble() / dashboardService.maskingFactor,
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: const DrawerMenuButton(),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Investments'),
            if (dashboardService.maskingFactor > 1.0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (dashboardService.members.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.people),
              initialValue: fundsService.selectedMemberId,
              onSelected: (val) =>
                  fundsService.setMember(val == 'all' ? null : val),
              itemBuilder: (context) => <PopupMenuEntry<String>>[
                const PopupMenuItem(value: 'all', child: Text('All Family')),
                ...dashboardService.members.map(
                  (m) => PopupMenuItem(
                    value: m['id'].toString(),
                    child: Text(m['name']),
                  ),
                ),
              ],
            ),
          if (fundsService.syncStatus != null &&
              fundsService.syncStatus!['status'] == 'running')
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => fundsService.fetchFunds(),
        child: fundsService.isLoading && fundsService.portfolio == null
            ? const Center(child: CircularProgressIndicator())
            : fundsService.error != null
            ? Center(
                child: Text(
                  fundsService.error!,
                  style: const TextStyle(color: Colors.red),
                ),
              )
            : _buildContent(context, fundsService.portfolio!, formatAmount),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    PortfolioSummary portfolio,
    Function(Decimal) format,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSummaryCard(context, portfolio, format),
        const SizedBox(height: 24),
        _buildPortfolioCharts(context, portfolio),
        const SizedBox(height: 24),
        const Text(
          "Holdings",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ...portfolio.holdings.map((h) => _buildHoldingItem(context, h, format)),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildSummaryCard(
    BuildContext context,
    PortfolioSummary p,
    Function(Decimal) format,
  ) {
    final isProfit = p.totalPl >= Decimal.zero;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blueGrey.shade900, Colors.blueGrey.shade800],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Current Value",
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    format(p.totalCurrent),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    "Total Returns %",
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "${(p.totalPl.toDouble() / (p.totalInvested.toDouble() > 0 ? p.totalInvested.toDouble() : 1) * 100).toStringAsFixed(2)}%",
                    style: TextStyle(
                      color: isProfit ? Colors.greenAccent : Colors.redAccent,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Invested",
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  Text(
                    format(p.totalInvested),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              // Show Total Returns and Day Change
              _buildValueColumn(
                "Total Returns",
                p.totalPl,
                (p.totalPl.toDouble() /
                        (p.totalInvested.toDouble() > 0
                            ? p.totalInvested.toDouble()
                            : 1) *
                        100)
                    .toStringAsFixed(2),
                format,
              ),
              _buildValueColumn(
                "Day's Change",
                p.dayChange,
                p.dayChangePercentage.toDouble().toStringAsFixed(2),
                format,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildValueColumn(
    String label,
    Decimal value,
    String percentage,
    Function(Decimal) format,
  ) {
    final isProfit = value >= Decimal.zero;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "${isProfit ? '+' : ''}${format(value)}",
              style: TextStyle(
                color: isProfit ? Colors.greenAccent : Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              "($percentage)",
              style: TextStyle(
                color: isProfit
                    ? Colors.greenAccent.withValues(alpha: 0.8)
                    : Colors.redAccent.withValues(alpha: 0.8),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ],
    );
  }

  int _touchedIndex = -1;

  Widget _buildPortfolioCharts(
    BuildContext context,
    PortfolioSummary portfolio,
  ) {
    if (portfolio.holdings.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final List<Color> colors = [
      AppTheme.primary,
      AppTheme.success,
      AppTheme.warning,
      AppTheme.danger,
      Colors.purple,
      Colors.orange,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPerformanceChart(context),
        const SizedBox(height: 24),
        Text(
          "Asset Allocation",
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          height: 240, // Slightly taller for interaction space
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: theme.dividerColor.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: PieChart(
                  PieChartData(
                    pieTouchData: PieTouchData(
                      touchCallback: (FlTouchEvent event, pieTouchResponse) {
                        setState(() {
                          if (!event.isInterestedForInteractions ||
                              pieTouchResponse == null ||
                              pieTouchResponse.touchedSection == null) {
                            _touchedIndex = -1;
                            return;
                          }
                          _touchedIndex = pieTouchResponse
                              .touchedSection!
                              .touchedSectionIndex;
                        });
                      },
                    ),
                    sectionsSpace: 2,
                    centerSpaceRadius: 40,
                    sections: portfolio.holdings.asMap().entries.map((entry) {
                      final index = entry.key;
                      final h = entry.value;
                      final isTouched = index == _touchedIndex;
                      final double fontSize = isTouched ? 16.0 : 10.0;
                      final double radius = isTouched ? 50.0 : 40.0;
                      final double percentage =
                          (h.currentValue.toDouble() /
                              (portfolio.totalCurrent.toDouble() > 0
                                  ? portfolio.totalCurrent.toDouble()
                                  : 1)) *
                          100;

                      return PieChartSectionData(
                        color: colors[index % colors.length],
                        value: h.currentValue.toDouble(),
                        radius: radius,
                        showTitle: percentage > 10 || isTouched,
                        title: isTouched
                            ? '${percentage.toStringAsFixed(1)}%'
                            : '${percentage.toStringAsFixed(0)}%',
                        titleStyle: TextStyle(
                          fontSize: fontSize,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          shadows: const [
                            Shadow(color: Colors.black45, blurRadius: 2),
                          ],
                        ),
                        badgeWidget: isTouched
                            ? _buildTouchBadge(h.schemeName)
                            : null,
                        badgePositionPercentageOffset: 1.3,
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: math.min(portfolio.holdings.length, 5),
                  itemBuilder: (context, index) {
                    final h = portfolio.holdings[index];
                    final isTouched = index == _touchedIndex;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 8,
                      ),
                      decoration: isTouched
                          ? BoxDecoration(
                              color: colors[index % colors.length].withValues(
                                alpha: 0.2,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            )
                          : null,
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            color: colors[index % colors.length],
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              h.schemeName,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: isTouched
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTouchBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text.length > 15 ? '${text.substring(0, 15)}...' : text,
        style: const TextStyle(color: Colors.white, fontSize: 10),
      ),
    );
  }

  Widget _buildPerformanceChart(BuildContext context) {
    final fundsService = context.watch<FundsService>();
    final dashboardService = context.watch<DashboardService>();
    final theme = Theme.of(context);

    if (fundsService.isChartLoading && fundsService.timeline.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (fundsService.timeline.isEmpty) return const SizedBox.shrink();

    // Parse Data
    final points = fundsService.timeline
        .map((e) {
          try {
            final date = DateTime.parse(e['date']).toLocal();
            final value =
                (e['value'] as num).toDouble() / dashboardService.maskingFactor;
            return FlSpot(date.millisecondsSinceEpoch.toDouble(), value);
          } catch (e) {
            return null;
          }
        })
        .whereType<FlSpot>()
        .toList();

    if (points.isEmpty) return const SizedBox.shrink();

    points.sort((a, b) => a.x.compareTo(b.x));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Portfolio Growth (1Y)",
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          height: 250,
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: theme.dividerColor.withValues(alpha: 0.5),
            ),
          ),
          child: LineChart(
            LineChartData(
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((LineBarSpot touchedSpot) {
                      final date = DateTime.fromMillisecondsSinceEpoch(
                        touchedSpot.x.toInt(),
                      );
                      return LineTooltipItem(
                        '${DateFormat('MMM d, y').format(date)}\n${NumberFormat.currency(symbol: dashboardService.currencySymbol, decimalDigits: 0).format(touchedSpot.y)}',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    }).toList();
                  },
                ),
              ),
              gridData: const FlGridData(show: false),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final date = DateTime.fromMillisecondsSinceEpoch(
                        value.toInt(),
                      );
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          DateFormat('MMM').format(date),
                          style: TextStyle(
                            color: theme.disabledColor,
                            fontSize: 10,
                          ),
                        ),
                      );
                    },
                    interval: (points.last.x - points.first.x) / 5,
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  spots: points,
                  isCurved: true,
                  color: AppTheme.primary,
                  barWidth: 2,
                  isStrokeCapRound: true,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primary.withValues(alpha: 0.3),
                        AppTheme.primary.withValues(alpha: 0.0),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHoldingItem(
    BuildContext context,
    FundHolding h,
    Function(Decimal) format,
  ) {
    final theme = Theme.of(context);
    final dashboard = context.watch<DashboardService>();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            h.schemeName,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          // Day Change Row (New)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Day's Change",
                style: const TextStyle(color: Colors.grey, fontSize: 11),
              ),
              Text(
                "${h.dayChange >= Decimal.zero ? '+' : ''}${format(h.dayChange)} (${h.dayChangePercentage.toDouble().toStringAsFixed(2)}%)",
                style: TextStyle(
                  color: h.dayChange >= Decimal.zero
                      ? AppTheme.success
                      : AppTheme.danger,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, thickness: 0.5),
          const SizedBox(height: 8),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Current",
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    format(h.currentValue),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    "Total Returns",
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    NumberFormat.currency(
                      symbol: dashboard.currencySymbol,
                      decimalDigits: 0,
                    ).format(h.profitLoss.toDouble() / dashboard.maskingFactor),
                    style: TextStyle(
                      color: h.profitLoss < Decimal.zero
                          ? AppTheme.danger
                          : AppTheme.success,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
