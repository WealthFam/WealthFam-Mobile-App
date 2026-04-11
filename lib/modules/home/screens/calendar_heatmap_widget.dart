import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:decimal/decimal.dart';
import 'package:mobile_app/core/theme/app_theme.dart';

class CalendarHeatmapWidget extends StatelessWidget {
  final Map<String, Decimal> data;
  final double maskingFactor;
  final DateTime? startDate;
  final DateTime? endDate;

  const CalendarHeatmapWidget({
    super.key,
    required this.data,
    this.maskingFactor = 1.0,
    this.startDate,
    this.endDate,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return _buildEmptyState(context);
    }

    final theme = Theme.of(context);
    
    // Calculate date range
    final end = endDate ?? DateTime.now();
    final gridEndDate = DateTime(end.year, end.month, end.day);
    final gridStartDate = startDate ?? gridEndDate.subtract(const Duration(days: 364));
    
    // Find max value for intensity scaling
    double maxVal = 0.01; // Avoid division by zero
    data.forEach((_, val) {
      final v = val.toDouble();
      if (v > maxVal) maxVal = v;
    });

    // Group dates by week
    final weeks = _generateWeeks(gridStartDate, gridEndDate);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMonthsHeader(gridStartDate, gridEndDate),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true, // Show latest weeks first on the right
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDaysColumn(theme),
                const SizedBox(width: 8),
                Row(
                  children: weeks.map((week) => _buildWeekColumn(context, week, maxVal)).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildLegend(context),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.5)),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today_outlined, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text("No spending activity recorded", style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  List<List<DateTime?>> _generateWeeks(DateTime start, DateTime end) {
    List<List<DateTime?>> weeks = [];
    DateTime current = start;
    
    // Align start to the beginning of the week (Monday)
    // In our grid, row 0 = Mon, row 6 = Sun
    int startOffset = current.weekday - 1; // 0 for Mon, 6 for Sun
    
    List<DateTime?> currentWeek = List.filled(7, null);
    
    // First partial week
    for (int i = startOffset; i < 7; i++) {
      currentWeek[i] = current;
      current = current.add(const Duration(days: 1));
      if (current.isAfter(end)) break;
    }
    weeks.add(currentWeek);
    
    while (current.isBefore(end) || current.isAtSameMomentAs(end)) {
      currentWeek = List.filled(7, null);
      for (int i = 0; i < 7; i++) {
        currentWeek[i] = current;
        current = current.add(const Duration(days: 1));
        if (current.isAfter(end)) break;
      }
      weeks.add(currentWeek);
    }
    
    return weeks;
  }

  Widget _buildMonthsHeader(DateTime start, DateTime end) {
    final rangeText = "${DateFormat('MMM yyyy').format(start)} - ${DateFormat('MMM yyyy').format(end)}";
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text("Fiscal Pulse", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        Text(rangeText, style: const TextStyle(color: Colors.grey, fontSize: 10)),
      ],
    );
  }

  Widget _buildDaysColumn(ThemeData theme) {
    const days = ['M', '', 'W', '', 'F', '', 'S'];
    return Column(
      children: days.map((d) => Container(
        height: 12,
        alignment: Alignment.centerLeft,
        child: Text(d, style: TextStyle(fontSize: 8, color: theme.colorScheme.onSurface.withOpacity(0.4))),
      )).toList(),
    );
  }

  Widget _buildWeekColumn(BuildContext context, List<DateTime?> week, double maxVal) {
    return Column(
      children: week.map((day) => _buildDayTile(context, day, maxVal)).toList(),
    );
  }

  Widget _buildDayTile(BuildContext context, DateTime? day, double maxVal) {
    if (day == null) {
      return Container(width: 10, height: 10, margin: const EdgeInsets.all(1));
    }
    
    final dateStr = DateFormat('yyyy-MM-dd').format(day);
    final amount = data[dateStr]?.toDouble() ?? 0.0;
    
    // Intensity level (0 to 4)
    int level = 0;
    if (amount > 0) {
      final ratio = amount / maxVal;
      if (ratio < 0.2) level = 1;
      else if (ratio < 0.5) level = 2;
      else if (ratio < 0.8) level = 3;
      else level = 4;
    }
    
    final color = _getIntensityColor(context, level);
    
    return Tooltip(
      message: '${DateFormat('MMM d, yyyy').format(day)}: $amount',
      child: Container(
        width: 10,
        height: 10,
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Color _getIntensityColor(BuildContext context, int level) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    if (level == 0) return isDark ? Colors.grey.withOpacity(0.1) : Colors.grey.withOpacity(0.1);
    
    final baseColor = AppTheme.primary;
    switch (level) {
      case 1: return baseColor.withOpacity(0.2);
      case 2: return baseColor.withOpacity(0.4);
      case 3: return baseColor.withOpacity(0.7);
      case 4: return baseColor;
      default: return Colors.transparent;
    }
  }

  Widget _buildLegend(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        const Text("Less", style: TextStyle(fontSize: 9, color: Colors.grey)),
        const SizedBox(width: 4),
        ...List.generate(5, (i) => Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: _getIntensityColor(context, i),
            borderRadius: BorderRadius.circular(2),
          ),
        )),
        const SizedBox(width: 4),
        const Text("More", style: TextStyle(fontSize: 9, color: Colors.grey)),
      ],
    );
  }
}
