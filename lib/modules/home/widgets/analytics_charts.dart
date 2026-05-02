import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_app/core/theme/app_theme.dart';
import 'package:mobile_app/modules/home/models/dashboard_data.dart';
import 'package:mobile_app/modules/home/services/dashboard_service.dart';
import 'package:provider/provider.dart';

class MonthTrendChart extends StatelessWidget {
  const MonthTrendChart({
    required this.trend,
    required this.maskingFactor,
    super.key,
  });

  final List<MonthTrendItem> trend;
  final double maskingFactor;

  @override
  Widget build(BuildContext context) {
    if (trend.isEmpty) {
      return const SizedBox(
        height: 150,
        child: Center(child: Text('No Trend Data')),
      );
    }

    double maxY = 0;
    for (var m in trend) {
      if (m.spent.toDouble() > maxY) maxY = m.spent.toDouble();
      if (m.budget.toDouble() > maxY) maxY = m.budget.toDouble();
    }
    maxY = maxY * 1.2;

    return Container(
      height: 200,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
        ),
      ),
      child: BarChart(
        BarChartData(
          maxY: maxY,
          barGroups: trend.asMap().entries.map((e) {
            final isSelected = e.value.isSelected;
            return BarChartGroupData(
              x: e.key,
              barRods: [
                BarChartRodData(
                  toY: e.value.spent.toDouble(),
                  color: isSelected
                      ? (e.value.spent > e.value.budget &&
                                e.value.budget > Decimal.zero
                            ? AppTheme.danger
                            : Theme.of(context).colorScheme.secondary)
                      : (e.value.spent > e.value.budget &&
                                e.value.budget > Decimal.zero
                            ? AppTheme.danger.withValues(alpha: 0.4)
                            : AppTheme.primary.withValues(alpha: 0.4)),
                  width: isSelected ? 18 : 14,
                  borderRadius: BorderRadius.circular(6),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: e.value.budget > Decimal.zero
                        ? e.value.budget.toDouble()
                        : maxY * 0.8,
                    color: isSelected
                        ? Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.1)
                        : Theme.of(
                            context,
                          ).dividerColor.withValues(alpha: 0.05),
                  ),
                ),
              ],
            );
          }).toList(),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 45,
                getTitlesWidget: (val, meta) => Text(
                  NumberFormat.compact().format(val / maskingFactor),
                  style: const TextStyle(
                    fontSize: 9,
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (val, meta) {
                  int idx = val.toInt();
                  if (idx >= 0 && idx < trend.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        trend[idx].month.split(' ')[0],
                        style: const TextStyle(
                          fontSize: 9,
                          color: Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
            rightTitles: const AxisTitles(
              
            ),
            topTitles: const AxisTitles(
              
            ),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            touchCallback: (FlTouchEvent event, barTouchResponse) {
              if (!event.isInterestedForInteractions ||
                  barTouchResponse == null ||
                  barTouchResponse.spot == null) {
                return;
              }
              final index = barTouchResponse.spot!.touchedBarGroupIndex;
              if (index >= 0 && index < trend.length) {
                final item = trend[index];
                if (event is FlTapUpEvent) {
                  try {
                    final date = DateFormat('MMM yyyy').parse(item.month);
                    final dashboard = context.read<DashboardService>();
                    dashboard.setMonth(date.month, date.year);
                  } catch (e) {
                    debugPrint('Error parsing month for tap: $e');
                  }
                }
              }
            },
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (group) => Theme.of(context).colorScheme.surface,
              tooltipBorder: BorderSide(color: Theme.of(context).dividerColor),
              tooltipPadding: const EdgeInsets.all(8),
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                return BarTooltipItem(
                  '${trend[groupIndex].month}\n',
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  children: [
                    TextSpan(
                      text: NumberFormat.compact().format(
                        rod.toY / maskingFactor,
                      ),
                      style: TextStyle(color: rod.color, fontSize: 10),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class DailyTrendLineChart extends StatelessWidget {
  const DailyTrendLineChart({
    required this.trend,
    required this.maskingFactor,
    super.key,
  });

  final List<SpendingTrendItem> trend;
  final double maskingFactor;

  @override
  Widget build(BuildContext context) {
    if (trend.isEmpty) {
      return const SizedBox(height: 150, child: Center(child: Text('No Data')));
    }

    double maxY = 0;
    for (var item in trend) {
      if (item.amount.toDouble() > maxY) maxY = item.amount.toDouble();
    }
    maxY = maxY * 1.2;

    return Container(
      height: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
        ),
      ),
      child: LineChart(
        LineChartData(
          maxY: maxY,
          minY: 0,
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (spot) => Theme.of(context).colorScheme.surface,
              tooltipBorder: BorderSide(color: Theme.of(context).dividerColor),
              getTooltipItems: (List<LineBarSpot> touchedSpots) {
                return touchedSpots.map((LineBarSpot touchedSpot) {
                  final item = trend[touchedSpot.x.toInt()];
                  final date = DateTime.parse(item.date).toLocal();
                  return LineTooltipItem(
                    '${DateFormat('MMM d').format(date)}\n',
                    TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    children: [
                      TextSpan(
                        text:
                            '₹${NumberFormat.compact().format(item.amount.toDouble() / maskingFactor)}',
                        style: const TextStyle(
                          color: AppTheme.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  );
                }).toList();
              },
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 45,
                getTitlesWidget: (value, meta) {
                  return Text(
                    NumberFormat.compact().format(value.toDouble()),
                    style: const TextStyle(
                      fontSize: 9,
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  int idx = value.toInt();
                  if (idx >= 0 && idx < trend.length) {
                    DateTime date = DateTime.parse(trend[idx].date).toLocal();
                    if (date.day == 1 ||
                        date.day == 10 ||
                        date.day == 20 ||
                        idx == trend.length - 1) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          DateFormat('MMM d').format(date),
                          style: const TextStyle(
                            fontSize: 8,
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    }
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
            rightTitles: const AxisTitles(
              
            ),
            topTitles: const AxisTitles(
              
            ),
          ),
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) => FlLine(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: trend
                  .asMap()
                  .entries
                  .map(
                    (e) => FlSpot(e.key.toDouble(), e.value.amount.toDouble()),
                  )
                  .toList(),
              isCurved: true,
              color: AppTheme.primary,
              barWidth: 4,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
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
    );
  }
}

class CategorySpendingPieChart extends StatelessWidget {
  const CategorySpendingPieChart({
    required this.distribution,
    required this.formatAmount,
    super.key,
  });

  final List<CategoryPieItem> distribution;
  final String Function(Decimal) formatAmount;

  @override
  Widget build(BuildContext context) {
    if (distribution.isEmpty) {
      return const SizedBox(height: 150, child: Center(child: Text('No Data')));
    }

    final List<Color> colors = [
      const Color(0xFF4F46E5),
      const Color(0xFF10B981),
      const Color(0xFFF59E0B),
      const Color(0xFFEF4444),
      const Color(0xFF8B5CF6),
      const Color(0xFFEC4899),
      const Color(0xFF0EA5E9),
      const Color(0xFFF43F5E),
    ];

    final totalAmount = distribution.fold(
      Decimal.zero,
      (sum, i) => sum + i.value,
    );
    final totalVal = totalAmount.toDouble();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 180,
            child: PieChart(
              PieChartData(
                sectionsSpace: 4,
                centerSpaceRadius: 50,
                sections: distribution.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = entry.value;
                  final percentage = totalVal > 0
                      ? (item.value.toDouble() / totalVal * 100)
                      : 0.0;
                  return PieChartSectionData(
                    color: colors[index % colors.length],
                    value: item.value.toDouble(),
                    title: '${percentage.toStringAsFixed(0)}%',
                    titleStyle: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    radius: 50,
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 24),
          ...distribution.take(5).toList().asMap().entries.map((e) {
            final percentage = totalVal > 0
                ? (e.value.value.toDouble() / totalVal * 100)
                : 0.0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: colors[e.key % colors.length],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      e.value.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    formatAmount(e.value.value),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${percentage.toStringAsFixed(1)}%',
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class SmartInsightWidget extends StatelessWidget {
  const SmartInsightWidget({required this.data, super.key});

  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    String insightText = 'Your budget is looking healthy!';
    IconData icon = Icons.auto_awesome;
    Color color = AppTheme.success;

    if (data.budget.percentage > Decimal.parse('100')) {
      insightText = 'Budget exceeded! Check spending.';
      icon = Icons.warning_amber_rounded;
      color = AppTheme.danger;
    } else if (data.budget.percentage > Decimal.parse('80')) {
      insightText = 'Running close to budget. Slow down!';
      icon = Icons.info_outline;
      color = AppTheme.warning;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              insightText,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
