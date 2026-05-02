

import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_app/core/theme/app_theme.dart';
import 'package:mobile_app/core/widgets/app_shell.dart';
import 'package:mobile_app/modules/home/models/fund_models.dart';
import 'package:mobile_app/modules/home/screens/fund_detail_screen.dart';
import 'package:mobile_app/modules/home/services/dashboard_service.dart';
import 'package:mobile_app/modules/home/services/funds_service.dart';
import 'package:provider/provider.dart';

class MutualFundsScreen extends StatefulWidget {
  const MutualFundsScreen({super.key});

  @override
  State<MutualFundsScreen> createState() => _MutualFundsScreenState();
}

class _MutualFundsScreenState extends State<MutualFundsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FundsService>().fetchFunds();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fundsService = context.watch<FundsService>();
    final dashboardService = context.watch<DashboardService>();
    final theme = Theme.of(context);

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
      body: RefreshIndicator(
        onRefresh: () => fundsService.fetchFunds(),
        child: fundsService.isLoading && fundsService.portfolio == null
            ? const Center(child: CircularProgressIndicator())
            : fundsService.error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.red, size: 48),
                        const SizedBox(height: 16),
                        Text(
                          fundsService.error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                        ElevatedButton(
                          onPressed: () => fundsService.fetchFunds(),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : _buildSliverContent(
                    context,
                    fundsService.portfolio!,
                    dashboardService,
                    formatAmount,
                  ),
      ),
    );
  }

  Widget _buildSliverContent(
    BuildContext context,
    PortfolioSummary portfolio,
    DashboardService dashboard,
    String Function(Decimal) format,
  ) {
    final theme = Theme.of(context);

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          leading: const DrawerMenuButton(),
          backgroundColor: theme.scaffoldBackgroundColor,
          elevation: 0,
          title: Text(
            'Investments',
            style: TextStyle(
              color: theme.textTheme.titleLarge?.color,
              fontWeight: FontWeight.bold,
            ),
          ),
          actions: [
            if (dashboard.members.isNotEmpty)
              PopupMenuButton<String>(
                icon: const Icon(Icons.people_outline),
                initialValue: context.read<FundsService>().selectedMemberId,
                onSelected: (val) => context
                    .read<FundsService>()
                    .setMember(val == 'all' ? null : val),
                itemBuilder: (context) => <PopupMenuEntry<String>>[
                  const PopupMenuItem(value: 'all', child: Text('All Family')),
                  ...dashboard.members.map(
                    (mRaw) {
                      final m = mRaw as Map<String, dynamic>;
                      return PopupMenuItem(
                        value: m['id'].toString(),
                        child: Text(m['name'] as String? ?? 'Unknown'),
                      );
                    },
                  ),
                ],
              ),
            const SizedBox(width: 8),
          ],
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverToBoxAdapter(
            child: _buildSummaryHeader(context, portfolio, format),
          ),
        ),
        SliverPersistentHeader(
          pinned: true,
          delegate: _SliverTabDelegate(
            TabBar(
              controller: _tabController,
              labelColor: theme.colorScheme.primary,
              unselectedLabelColor: theme.disabledColor,
              indicatorColor: theme.colorScheme.primary,
              indicatorSize: TabBarIndicatorSize.label,
              tabs: const [
                Tab(text: 'Overview'),
                Tab(text: 'Holdings'),
              ],
            ),
          ),
        ),
        SliverFillRemaining(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildOverviewTab(context, portfolio, format),
              _buildHoldingsTab(context, portfolio, format),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryHeader(
    BuildContext context,
    PortfolioSummary p,
    String Function(Decimal) format,
  ) {
    final isProfit = p.totalPl >= Decimal.zero;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary.withValues(alpha: 0.9),
            AppTheme.primary.withValues(alpha: 0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.3),
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
              const Text(
                'Current Portfolio Value',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (p.xirr != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'XIRR: ${p.xirr!.toStringAsFixed(2)}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            format(p.totalCurrent),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _buildHeaderStat(
                'Total Returns',
                '${isProfit ? '+' : ''}${format(p.totalPl)}',
                isProfit ? Colors.greenAccent : Colors.redAccent,
              ),
              const SizedBox(width: 24),
              _buildHeaderStat(
                'Day Change',
                '${p.dayChange >= Decimal.zero ? '+' : ''}${format(p.dayChange)}',
                p.dayChange >= Decimal.zero ? Colors.greenAccent : Colors.redAccent,
              ),
              const SizedBox(width: 24),
              _buildHeaderStat(
                'Invested',
                format(p.totalInvested),
                Colors.white,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderStat(String label, String value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white60,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildOverviewTab(
    BuildContext context,
    PortfolioSummary portfolio,
    String Function(Decimal) format,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildPerformanceChart(context),
        const SizedBox(height: 24),
        _buildInsights(context, portfolio, format),
        const SizedBox(height: 24),
        _buildAssetAllocation(context, portfolio),
        const SizedBox(height: 24),
        _buildFundDistribution(context, portfolio),
        const SizedBox(height: 24),
        _buildPortfolioStats(context, portfolio, format),
        const SizedBox(height: 80), // Space for bottom
      ],
    );
  }

  Widget _buildInsights(
    BuildContext context,
    PortfolioSummary portfolio,
    String Function(Decimal) format,
  ) {
    if (portfolio.topGainers.isEmpty &&
        portfolio.topLosers.isEmpty &&
        portfolio.textInsights.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (portfolio.textInsights.isNotEmpty) ...[
          const Text(
            'Portfolio Analysis',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ...portfolio.textInsights.map((insight) => Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppTheme.primary.withValues(alpha: 0.1)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lightbulb_outline,
                        color: AppTheme.primary, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        insight,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 12),
        ],
        const Text(
          'Top Performers',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        if (portfolio.topGainers.isNotEmpty)
          ...portfolio.topGainers.map((h) => _buildInsightCard(context, h, true, format)),
        if (portfolio.topLosers.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            'Underperformers',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ...portfolio.topLosers.map((h) => _buildInsightCard(context, h, false, format)),
        ],
      ],
    );
  }

  Widget _buildInsightCard(
    BuildContext context,
    FundHolding h,
    bool isGainer,
    String Function(Decimal) format,
  ) {
    final theme = Theme.of(context);
    final inv = h.investedValue.toDouble();
    final plPercent = inv > 0 ? (h.profitLoss.toDouble() / inv) * 100 : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (isGainer ? AppTheme.success : AppTheme.danger).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isGainer ? Icons.trending_up : Icons.trending_down,
              color: isGainer ? AppTheme.success : AppTheme.danger,
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  h.schemeName,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${plPercent >= 0 ? '+' : ''}${plPercent.toStringAsFixed(1)}% Returns',
                  style: TextStyle(
                    fontSize: 10,
                    color: isGainer ? AppTheme.success : AppTheme.danger,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            format(h.currentValue),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildHoldingsTab(
    BuildContext context,
    PortfolioSummary portfolio,
    String Function(Decimal) format,
  ) {
    if (portfolio.holdings.isEmpty) {
      return const Center(child: Text('No holdings found.'));
    }

    // Grouping Logic
    final Map<String, List<FundHolding>> groupedHoldings = {};
    for (var h in portfolio.holdings) {
      final cat = h.category ?? 'Uncategorized';
      groupedHoldings.putIfAbsent(cat, () => []).add(h);
    }

    final categories = groupedHoldings.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final cat = categories[index];
        final holdings = groupedHoldings[cat]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 12, left: 4),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 16,
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    cat.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: Colors.grey,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${holdings.length} Funds',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
            ...holdings.map((h) => _buildHoldingCard(context, h, format)),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Widget _buildHoldingCard(
    BuildContext context,
    FundHolding h,
    String Function(Decimal) format,
  ) {
    final theme = Theme.of(context);
    final isProfit = h.profitLoss >= Decimal.zero;
    final isDayProfit = h.dayChange >= Decimal.zero;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (context) => FundDetailScreen(
                      schemeCode: h.schemeCode,
                      schemeName: h.schemeName,
                    ),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                h.schemeName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                h.schemeCode,
                                style: TextStyle(
                                  color: theme.disabledColor,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (h.xirr != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${h.xirr!.toStringAsFixed(1)}% XIRR',
                              style: const TextStyle(
                                color: AppTheme.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1, thickness: 0.5),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildCompactStat(
                          'Current Value',
                          format(h.currentValue),
                          null,
                        ),
                        _buildCompactStat(
                          'Total Returns',
                          '${isProfit ? '+' : ''}${format(h.profitLoss)}',
                          isProfit ? AppTheme.success : AppTheme.danger,
                        ),
                        _buildCompactStat(
                          "Day's Change",
                          '${isDayProfit ? '+' : ''}${h.dayChangePercentage.toDouble().toStringAsFixed(2)}%',
                          isDayProfit ? AppTheme.success : AppTheme.danger,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (h.folios.isNotEmpty)
            Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                title: Text(
                  '${h.folios.length} ${h.folios.length > 1 ? 'Folios' : 'Folio'}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey),
                ),
                tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                childrenPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: h.folios
                    .map((f) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Folio: ${f.folioNumber}',
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.grey)),
                              Text(format(f.currentValue),
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCompactStat(String label, String value, Color? valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  Widget _buildPortfolioStats(
    BuildContext context,
    PortfolioSummary p,
    String Function(Decimal) format,
  ) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          _buildStatRow('Invested Value', format(p.totalInvested)),
          const Divider(),
          _buildStatRow('Current Value', format(p.totalCurrent)),
          const Divider(),
          _buildStatRow(
            'Overall Returns',
            format(p.totalPl),
            color: p.totalPl >= Decimal.zero ? AppTheme.success : AppTheme.danger,
          ),
          const Divider(),
          _buildStatRow(
            'Day Change',
            '${p.dayChange >= Decimal.zero ? '+' : ''}${format(p.dayChange)}',
            color: p.dayChange >= Decimal.zero ? AppTheme.success : AppTheme.danger,
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssetAllocation(BuildContext context, PortfolioSummary portfolio) {
    final theme = Theme.of(context);
    final allocation = portfolio.assetAllocation ?? {};
    if (allocation.isEmpty) return const SizedBox.shrink();

    final List<Color> colors = [
      AppTheme.primary,
      AppTheme.success,
      AppTheme.warning,
      AppTheme.danger,
      Colors.purple,
      Colors.orange,
    ];

    final entries = allocation.entries.where((e) => e.value > 0).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Strategic Asset Allocation',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Container(
          height: 180,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              Expanded(
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 4,
                    centerSpaceRadius: 35,
                    sections: entries.asMap().entries.map((entry) {
                      final index = entry.key;
                      final val = entry.value.value;

                      return PieChartSectionData(
                        color: colors[index % colors.length],
                        value: val,
                        radius: 12,
                        showTitle: false,
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final e = entries[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: colors[index % colors.length],
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${e.key[0].toUpperCase()}${e.key.substring(1)} (${e.value.toStringAsFixed(1)}%)',
                              style: const TextStyle(fontSize: 11),
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

  Widget _buildFundDistribution(BuildContext context, PortfolioSummary portfolio) {
    final theme = Theme.of(context);
    final holdings = portfolio.holdings;
    if (holdings.isEmpty) return const SizedBox.shrink();

    final totalVal = portfolio.totalCurrent.toDouble();
    if (totalVal <= 0) return const SizedBox.shrink();

    final List<Color> colors = [
      Colors.blue,
      Colors.green,
      Colors.amber,
      Colors.red,
      Colors.indigo,
      Colors.teal,
      Colors.pink,
    ];

    // Sort by value to show top holdings
    final sortedHoldings = List<FundHolding>.from(holdings)
      ..sort((a, b) => b.currentValue.compareTo(a.currentValue));

    // Limit to top 5 and group rest as "Others"
    final topHoldings = sortedHoldings.take(5).toList();
    final othersVal = sortedHoldings.length > 5
        ? sortedHoldings.skip(5).fold(0.0, (sum, h) => sum + h.currentValue.toDouble())
        : 0.0;

    final List<MapEntry<String, double>> entries = topHoldings
        .map((h) => MapEntry(h.schemeName, (h.currentValue.toDouble() / totalVal) * 100))
        .toList();
    
    if (othersVal > 0) {
      entries.add(MapEntry('Others', (othersVal / totalVal) * 100));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Portfolio Concentration',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Container(
          height: 180,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              Expanded(
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 40,
                    sections: entries.asMap().entries.map((entry) {
                      final index = entry.key;
                      return PieChartSectionData(
                        color: colors[index % colors.length],
                        value: entry.value.value,
                        radius: 8,
                        showTitle: false,
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final e = entries[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: colors[index % colors.length],
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${e.key} (${e.value.toStringAsFixed(1)}%)',
                              style: const TextStyle(fontSize: 10),
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

  Widget _buildPerformanceChart(BuildContext context) {
    final fundsService = context.watch<FundsService>();
    final dashboardService = context.watch<DashboardService>();
    final theme = Theme.of(context);

    if (fundsService.isChartLoading && fundsService.timeline.isEmpty) {
      return const SizedBox(
        height: 250,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (fundsService.timeline.isEmpty) return const SizedBox.shrink();

    final points = fundsService.timeline
        .map((e) {
          try {
            final date = DateTime.parse(e['date'] as String).toLocal();
            final value =
                (e['value'] as num).toDouble() / dashboardService.maskingFactor;
            return FlSpot(date.millisecondsSinceEpoch.toDouble(), value);
          } catch (e) {
            return null;
          }
        })
        .whereType<FlSpot>()
        .toList()
      ..sort((a, b) => a.x.compareTo(b.x));

    final benchmarkPoints = fundsService.timeline
        .map((e) {
          try {
            final date = DateTime.parse(e['date'] as String).toLocal();
            final bm = e['benchmarks'] as Map<String, dynamic>?;
            final niftyValue = bm?['120716'] as num?;
            if (niftyValue == null) return null;

            // Normalize Nifty to match portfolio scale at the start of the chart
            // (Basic normalization: Relative % change)
            return FlSpot(date.millisecondsSinceEpoch.toDouble(),
                niftyValue.toDouble() / dashboardService.maskingFactor);
          } catch (e) {
            return null;
          }
        })
        .whereType<FlSpot>()
        .toList()
      ..sort((a, b) => a.x.compareTo(b.x));

    if (points.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Performance History',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Container(
          height: 250,
          padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
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
                        '${DateFormat('MMM d').format(date)}\n${NumberFormat.currency(symbol: dashboardService.currencySymbol, decimalDigits: 0).format(touchedSpot.y)}',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      );
                    }).toList();
                  },
                ),
              ),
              gridData: const FlGridData(show: false),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                topTitles: const AxisTitles(),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final date = DateTime.fromMillisecondsSinceEpoch(
                        value.toInt(),
                      );
                      // Only show month every few points
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          DateFormat('MMM').format(date),
                          style: TextStyle(
                            color: theme.disabledColor,
                            fontSize: 9,
                          ),
                        ),
                      );
                    },
                    interval: (points.last.x - points.first.x) / 4,
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  spots: points,
                  isCurved: true,
                  color: AppTheme.primary,
                  barWidth: 3,
                  isStrokeCapRound: true,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primary.withValues(alpha: 0.2),
                        AppTheme.primary.withValues(alpha: 0.0),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
                if (benchmarkPoints.isNotEmpty)
                  LineChartBarData(
                    spots: benchmarkPoints,
                    isCurved: true,
                    color: Colors.orange,
                    dashArray: [5, 5],
                    dotData: const FlDotData(show: false),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SliverTabDelegate extends SliverPersistentHeaderDelegate {
  _SliverTabDelegate(this._tabBar);

  final TabBar _tabBar;

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverTabDelegate oldDelegate) {
    return false;
  }
}
