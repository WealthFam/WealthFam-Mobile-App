import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_app/core/theme/app_theme.dart';
import 'package:mobile_app/modules/home/models/fund_models.dart';
import 'package:mobile_app/modules/home/services/funds_service.dart';
import 'package:provider/provider.dart';

class FundDetailScreen extends StatefulWidget {
  const FundDetailScreen({
    required this.schemeCode,
    required this.schemeName,
    super.key,
  });

  final String schemeCode;
  final String schemeName;

  @override
  State<FundDetailScreen> createState() => _FundDetailScreenState();
}

class _FundDetailScreenState extends State<FundDetailScreen> {
  late Future<FundDetailResponse?> _detailsFuture;

  @override
  void initState() {
    super.initState();
    _detailsFuture = context.read<FundsService>().fetchFundDetails(widget.schemeCode);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: FutureBuilder<FundDetailResponse?>(
        future: _detailsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError || snapshot.data == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    'Failed to load fund details',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _detailsFuture = context
                            .read<FundsService>()
                            .fetchFundDetails(widget.schemeCode);
                      });
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final d = snapshot.data!;

          return CustomScrollView(
            slivers: [
              _buildAppBar(context, d, theme),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSummaryCard(d, theme, currencyFormat),
                      const SizedBox(height: 24),
                      _buildPerformanceSection(d, theme, currencyFormat),
                      const SizedBox(height: 24),
                      _buildFolioBreakdown(d, theme, currencyFormat),
                      const SizedBox(height: 24),
                      _buildTransactionHistory(d, theme, currencyFormat),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, FundDetailResponse d, ThemeData theme) {
    return SliverAppBar(
      expandedHeight: 120,
      pinned: true,
      stretch: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: false,
        titlePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        title: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              d.schemeName,
              style: TextStyle(
                color: theme.textTheme.titleLarge?.color,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${d.category} • ${d.schemeCode}',
              style: TextStyle(
                color: theme.disabledColor,
                fontSize: 10,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(
      FundDetailResponse d, ThemeData theme, NumberFormat format) {
    final isProfit = d.profitLoss >= Decimal.zero;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSummaryStat('Current Value', format.format(d.currentValue.toDouble()), null),
              _buildSummaryStat('Returns',
                  '${isProfit ? '+' : ''}${format.format(d.profitLoss.toDouble())}',
                  isProfit ? AppTheme.success : AppTheme.danger),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSummaryStat('Invested', format.format(d.investedValue.toDouble()), null),
              _buildSummaryStat(
                "Day's Change",
                '${d.dayChange >= Decimal.zero ? '+' : ''}${format.format(d.dayChange.toDouble())} (${d.dayChangePercentage.toStringAsFixed(2)}%)',
                d.dayChange >= Decimal.zero ? AppTheme.success : AppTheme.danger,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryStat(String label, String value, Color? valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  Widget _buildPerformanceSection(
      FundDetailResponse d, ThemeData theme, NumberFormat format) {
    if (d.timeline.isEmpty) return const SizedBox.shrink();

    // Spots for Fund
    final firstNav = d.timeline.first.value;
    final fundSpots = d.timeline.map((e) {
      final date = DateTime.parse(e.date).millisecondsSinceEpoch.toDouble();
      // Normalize to 100 for comparison
      final normalizedValue = (e.value / firstNav) * 100;
      return FlSpot(date, normalizedValue);
    }).toList();

    // Spots for Benchmark (Nifty 50)
    final firstBm = d.timeline.first.benchmarkValue ?? 1.0;
    final bmSpots = d.timeline.where((e) => e.benchmarkValue != null).map((e) {
      final date = DateTime.parse(e.date).millisecondsSinceEpoch.toDouble();
      final normalizedValue = (e.benchmarkValue! / firstBm) * 100;
      return FlSpot(date, normalizedValue);
    }).toList();

    // Event Markers (Buy/Sell)
    final eventMarkers = d.events.map((e) {
      final date = DateTime.parse(e.date).millisecondsSinceEpoch.toDouble();
      return VerticalLine(
        x: date,
        color: e.type == 'BUY' ? Colors.green.withValues(alpha: 0.3) : Colors.red.withValues(alpha: 0.3),
        strokeWidth: 1,
        dashArray: [4, 4],
      );
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Performance vs Nifty 50',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                _buildLegendItem('Fund', AppTheme.primary),
                const SizedBox(width: 12),
                _buildLegendItem('Nifty 50', Colors.orange),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          height: 300,
          padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
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
                    return touchedSpots.map((spot) {
                      final isFund = spot.barIndex == 0;
                      final date = DateTime.fromMillisecondsSinceEpoch(spot.x.toInt());
                      return LineTooltipItem(
                        '${DateFormat('MMM d, y').format(date)}\n${isFund ? 'Fund' : 'Nifty'}: ${spot.y.toStringAsFixed(1)}%',
                        TextStyle(
                          color: isFund ? AppTheme.primary : Colors.orange,
                          fontWeight: FontWeight.bold,
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
                      final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          DateFormat('MMM').format(date),
                          style: TextStyle(color: theme.disabledColor, fontSize: 9),
                        ),
                      );
                    },
                    interval: (fundSpots.last.x - fundSpots.first.x) / 5,
                  ),
                ),
              ),
              extraLinesData: ExtraLinesData(verticalLines: eventMarkers),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  spots: fundSpots,
                  isCurved: true,
                  color: AppTheme.primary,
                  barWidth: 3,
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
                LineChartBarData(
                  spots: bmSpots,
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

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }

  Widget _buildFolioBreakdown(
      FundDetailResponse d, ThemeData theme, NumberFormat format) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Folios',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ...d.folios.map((f) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Folio: ${f.folioNumber}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${f.units.toStringAsFixed(3)} units',
                        style: TextStyle(color: theme.disabledColor, fontSize: 12),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        format.format(f.currentValue.toDouble()),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${f.profitLoss >= Decimal.zero ? '+' : ''}${format.format(f.profitLoss.toDouble())}',
                        style: TextStyle(
                          color: f.profitLoss >= Decimal.zero
                              ? AppTheme.success
                              : AppTheme.danger,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            )),
      ],
    );
  }

  Widget _buildTransactionHistory(
      FundDetailResponse d, ThemeData theme, NumberFormat format) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Transactions',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ...d.events.map((e) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: e.type == 'BUY'
                      ? AppTheme.success.withValues(alpha: 0.1)
                      : AppTheme.danger.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  e.type == 'BUY' ? Icons.add : Icons.remove,
                  color: e.type == 'BUY' ? AppTheme.success : AppTheme.danger,
                  size: 20,
                ),
              ),
              title: Text(
                e.type == 'BUY' ? 'Purchase' : 'Redemption',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '${DateFormat('MMM d, y').format(DateTime.parse(e.date))} • ${e.units.toStringAsFixed(3)} units',
              ),
              trailing: Text(
                format.format(e.amount),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            )),
      ],
    );
  }
}
