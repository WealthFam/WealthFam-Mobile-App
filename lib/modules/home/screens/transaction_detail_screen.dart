import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_app/core/theme/app_theme.dart';
import 'package:mobile_app/core/widgets/transaction_settings_sheet.dart';
import 'package:mobile_app/modules/home/models/dashboard_data.dart';
import 'package:mobile_app/modules/home/services/categories_service.dart';
import 'package:mobile_app/modules/home/services/dashboard_service.dart';
import 'package:mobile_app/modules/vault/services/vault_service.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';

class TransactionDetailScreen extends StatefulWidget {
  const TransactionDetailScreen({required this.transaction, super.key});
  final RecentTransaction transaction;

  @override
  State<TransactionDetailScreen> createState() => _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  Map<String, dynamic>? _vendorStats;
  List<VaultDocument> _attachedDocs = [];
  bool _isLoadingStats = false;
  bool _isLoadingDocs = false;

  final List<dynamic> _vendorTransactions = [];
  int _vendorSkip = 0;
  bool _isLoadingMoreVendorTxns = false;
  bool _hasMoreVendorTxns = true;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchData();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
        _fetchVendorStats(loadMore: true);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    _fetchVendorStats();
    _fetchAttachedDocs();
  }

  Future<void> _fetchVendorStats({bool loadMore = false}) async {
    if (loadMore && (_isLoadingMoreVendorTxns || !_hasMoreVendorTxns)) return;
    
    final recipient = widget.transaction.recipient ?? widget.transaction.description;
    if (recipient.isEmpty) return;
    
    if (loadMore) {
      setState(() => _isLoadingMoreVendorTxns = true);
    } else {
      setState(() {
        _isLoadingStats = true;
        _vendorSkip = 0;
        _vendorTransactions.clear();
      });
    }
    
    final dashboard = context.read<DashboardService>();
    final result = await dashboard.fetchVendorStats(recipient, skip: _vendorSkip, limit: 10);
    
    if (mounted) {
      result.fold(
        (failure) => debugPrint('Failed to fetch vendor stats: ${failure.message}'),
        (stats) {
          setState(() {
            if (!loadMore) _vendorStats = stats;
            final newTxns = stats['recent_transactions'] as List<dynamic>;
            _vendorTransactions.addAll(newTxns);
            _hasMoreVendorTxns = newTxns.length == 10;
            _vendorSkip += newTxns.length;
          });
        },
      );
      setState(() {
        _isLoadingStats = false;
        _isLoadingMoreVendorTxns = false;
      });
    }
  }

  Future<void> _fetchAttachedDocs() async {
    setState(() => _isLoadingDocs = true);
    final vault = context.read<VaultService>();
    final docs = await vault.getLinkedDocuments(widget.transaction.id);
    
    if (mounted) {
      setState(() {
        _attachedDocs = docs;
        _isLoadingDocs = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final transaction = widget.transaction;
    final dashboard = context.watch<DashboardService>();
    final theme = Theme.of(context);
    final currencyFormat = NumberFormat.currency(
      symbol: dashboard.currencySymbol,
      decimalDigits: 2,
    );

    final amount = transaction.amount.toDouble() / dashboard.maskingFactor;
    final formattedAmount = currencyFormat.format(amount);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            stretch: true,
            backgroundColor: AppTheme.primary,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined, color: Colors.white),
                onPressed: () {
                  TransactionSettingsSheet.show(context, transaction);
                },
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [StretchMode.zoomBackground, StretchMode.blurBackground],
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppTheme.primary,
                      AppTheme.primary.withValues(alpha: 0.8),
                      theme.colorScheme.secondary,
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 20),
                      Text(
                        formattedAmount,
                        style: const TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Builder(
                              builder: (context) {
                                final icon = transaction.categoryIcon ??
                                    context.read<CategoriesService>()
                                        .getIconForCategory(transaction.category);
                                if (icon != null && icon.isNotEmpty) {
                                  return Text(
                                    '$icon ',
                                    style: const TextStyle(fontSize: 16),
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                            Text(
                              transaction.category.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoCard(theme, transaction),
                  const SizedBox(height: 32),
                  if (widget.transaction.recipient != null || widget.transaction.description.isNotEmpty) ...[
                    _buildVendorInsightsSection(theme),
                    const SizedBox(height: 32),
                  ],
                  _buildEvidenceSection(theme),
                  const SizedBox(height: 32),
                  _buildTimelineSection(theme, transaction),
                  const SizedBox(height: 40),
                  if (_vendorTransactions.isNotEmpty) ...[
                    Row(
                      children: [
                        Container(
                          width: 4,
                          height: 24,
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'VENDOR HISTORY',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                ],
              ),
            ),
          ),
          if (_vendorTransactions.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index < _vendorTransactions.length) {
                      final txn = _vendorTransactions[index];
                      return _buildVendorTransactionItem(txn);
                    }
                    if (_isLoadingMoreVendorTxns) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(child: CircularProgressIndicator.adaptive()),
                      );
                    }
                    if (!_hasMoreVendorTxns) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                          child: Text(
                            'No more transactions for this vendor',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ),
                      );
                    }
                    return null;
                  },
                  childCount: _vendorTransactions.length + (_isLoadingMoreVendorTxns || !_hasMoreVendorTxns ? 1 : 0),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  Widget _buildVendorInsightsSection(ThemeData theme) {
    if (_isLoadingStats) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (_vendorStats == null) return const SizedBox.shrink();

    final dashboard = context.read<DashboardService>();
    final chartData = _vendorStats!['chart_data'] as List<dynamic>;
    final totalSpent = _vendorStats!['total_spent'] as num;
    final avgTxn = _vendorStats!['average_transaction'] as num;

    final currencyFormat = NumberFormat.currency(
      symbol: dashboard.currencySymbol,
      decimalDigits: 0,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'INSIGHTS: ${widget.transaction.recipient ?? widget.transaction.description}'.toUpperCase(),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  color: Colors.grey,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Total: ${currencyFormat.format(totalSpent.abs() / dashboard.maskingFactor)}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Avg: ${currencyFormat.format(avgTxn.abs() / dashboard.maskingFactor)}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        // Trend Chart
        if (chartData.isNotEmpty) ...[
          Container(
            height: 180,
            padding: const EdgeInsets.only(top: 24, right: 10, left: 10),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(20),
            ),
            child: LineChart(
              LineChartData(
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (spot) => AppTheme.primary.withValues(alpha: 0.9),
                    getTooltipItems: (spots) => spots.map((s) {
                      return LineTooltipItem(
                        currencyFormat.format(s.y / dashboard.maskingFactor),
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      );
                    }).toList(),
                  ),
                ),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: 1,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.grey.withValues(alpha: 0.05),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= chartData.length) return const SizedBox.shrink();
                        final monthStr = (chartData[index] as Map<String, dynamic>)['month'] as String;
                        final monthPart = monthStr.split('-').last;
                        final months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            months[int.parse(monthPart) - 1],
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: Colors.grey,
                              letterSpacing: 0.5,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: const AxisTitles(),
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: chartData.asMap().entries.map((e) {
                      final val = e.value as Map<String, dynamic>;
                      return FlSpot(e.key.toDouble(), (val['amount'] as num).toDouble());
                    }).toList(),
                    isCurved: true,
                    curveSmoothness: 0.4,
                    color: AppTheme.primary,
                    barWidth: 4,
                    isStrokeCapRound: true,
                    shadow: Shadow(
                      color: AppTheme.primary.withValues(alpha: 0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 7),
                    ),
                    dotData: FlDotData(
                      checkToShowDot: (spot, barData) {
                        final spots = barData.spots;
                        final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
                        final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
                        return spot.y == maxY || spot.y == minY;
                      },
                      getDotPainter: (spot, percent, barData, index) {
                        final spots = barData.spots;
                        final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
                        final isMax = spot.y == maxY;
                        return FlDotCirclePainter(
                          radius: isMax ? 6 : 4,
                          color: isMax ? AppTheme.primary : Colors.white,
                          strokeWidth: 3,
                          strokeColor: isMax ? Colors.white : AppTheme.primary,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppTheme.primary.withValues(alpha: 0.25),
                          AppTheme.primary.withValues(alpha: 0.05),
                          AppTheme.primary.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildTrendInfo('Highest', chartData.map((e) => ((e as Map<String, dynamic>)['amount'] as num).toDouble()).reduce((a, b) => a > b ? a : b), currencyFormat, dashboard),
                _buildTrendInfo('Lowest', chartData.map((e) => ((e as Map<String, dynamic>)['amount'] as num).toDouble()).reduce((a, b) => a < b ? a : b), currencyFormat, dashboard),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTrendInfo(String label, double amount, NumberFormat format, DashboardService dashboard) {
    return Column(
      crossAxisAlignment: label == 'Highest' ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1),
        ),
        Text(
          format.format(amount / dashboard.maskingFactor),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildVendorTransactionItem(dynamic txnRaw) {
    final txn = txnRaw as Map<String, dynamic>;
    final dashboard = context.read<DashboardService>();
    final date = DateTime.parse(txn['date'] as String);
    final amount = txn['amount'] as num;
    final currencyFormat = NumberFormat.currency(
      symbol: dashboard.currencySymbol,
      decimalDigits: 0,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              DateFormat('dd MMM').format(date).toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                color: AppTheme.primary,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (txn['description'] as String?) ?? 'No description',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (txn['category'] != null)
                  Text(
                    (txn['category'] as String).toUpperCase(),
                    style: TextStyle(fontSize: 9, color: Colors.grey.shade500, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  ),
              ],
            ),
          ),
          Text(
            currencyFormat.format(amount.abs() / dashboard.maskingFactor),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: amount < 0 ? AppTheme.danger : AppTheme.success,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(ThemeData theme, RecentTransaction tx) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildInfoRow(Icons.description_outlined, 'DESCRIPTION', tx.description),
          _buildDivider(),
          _buildInfoRow(Icons.calendar_today_outlined, 'DATE & TIME', tx.formattedDate),
          _buildDivider(),
          _buildInfoRow(Icons.account_balance_wallet_outlined, 'FUND SOURCE', tx.accountName ?? 'Manual Entry'),
          if (tx.accountOwnerName != null) ...[
            _buildDivider(),
            _buildInfoRow(Icons.person_outline, 'OWNED BY', tx.accountOwnerName!),
          ],
          _buildDivider(),
          _buildInfoRow(
            Icons.bolt_outlined,
            'INGESTION',
            tx.source?.toUpperCase() ?? 'DIRECT',
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Divider(height: 1, color: Colors.grey.withValues(alpha: 0.1)),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: AppTheme.primary),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: Colors.grey,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineSection(ThemeData theme, RecentTransaction tx) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Transaction Timeline',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        _buildTimelineItem(
          'Detected',
          'Transaction recognized via ${tx.source ?? 'manual entry'}',
          tx.formattedDate,
          true,
          false,
        ),
        _buildTimelineItem(
          'Categorized',
          'Auto-assigned to ${tx.category}',
          '',
          false,
          false,
        ),
        _buildTimelineItem(
          'Synced',
          'Successfully archived to cloud ledger',
          '',
          false,
          true,
        ),
      ],
    );
  }

  Widget _buildTimelineItem(
    String title,
    String subtitle,
    String time,
    bool isFirst,
    bool isLast,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                color: AppTheme.primary,
                shape: BoxShape.circle,
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 40,
                color: AppTheme.primary.withValues(alpha: 0.2),
              ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (time.isNotEmpty)
                    Text(time, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEvidenceSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Evidence & Receipts',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            IconButton(
              onPressed: _showAddEvidenceDialog,
              icon: const Icon(Icons.add_circle_outline, color: AppTheme.primary),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_isLoadingDocs)
          const Center(child: CircularProgressIndicator.adaptive())
        else if (_attachedDocs.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              children: [
                Icon(Icons.receipt_long_outlined, color: Colors.grey, size: 40),
                SizedBox(height: 8),
                Text(
                  'No evidence linked yet',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.5,
            ),
            itemCount: _attachedDocs.length,
            itemBuilder: (context, index) {
              final doc = _attachedDocs[index];
              return _buildDocCard(doc);
            },
          ),
      ],
    );
  }

  Widget _buildDocCard(VaultDocument doc) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => _openDocument(doc),
      child: Container(
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _getDocIcon(doc.mimeType),
                    color: AppTheme.primary.withValues(alpha: 0.5),
                    size: 32,
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text(
                      doc.filename,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.close, size: 16, color: AppTheme.danger),
                onPressed: () => _detachDoc(doc.id),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDocument(VaultDocument doc) async {
    final vault = context.read<VaultService>();
    final result = await vault.saveDocument(doc);
    
    result.fold(
      (failure) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to download: ${failure.message}')),
      ),
      (path) async {
        await OpenFilex.open(path);
      },
    );
  }

  IconData _getDocIcon(String? mimeType) {
    if (mimeType == null) return Icons.insert_drive_file_outlined;
    if (mimeType.contains('pdf')) return Icons.picture_as_pdf_outlined;
    if (mimeType.contains('image')) return Icons.image_outlined;
    if (mimeType.contains('sheet') || mimeType.contains('excel') || mimeType.contains('csv')) {
      return Icons.table_chart_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  Future<void> _detachDoc(String docId) async {
    final vault = context.read<VaultService>();
    final result = await vault.linkTransaction(docId, null);
    
    result.fold(
      (failure) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to detach: ${failure.message}')),
      ),
      (_) => _fetchAttachedDocs(),
    );
  }

  void _showAddEvidenceDialog() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Add Evidence',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Upload New File'),
              onTap: () {
                Navigator.pop(context);
                _pickAndUploadFile();
              },
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Link from Vault'),
              onTap: () {
                Navigator.pop(context);
                _showVaultPicker();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showVaultPicker() {
    // Show a dialog to pick a document from the vault
    showDialog<void>(
      context: context,
      builder: (context) => _VaultDocPicker(
        onDocSelected: (doc) async {
          final vault = context.read<VaultService>();
          final result = await vault.linkTransaction(doc.id, widget.transaction.id);
          result.fold(
            (failure) => debugPrint('Link failed'),
            (_) => _fetchAttachedDocs(),
          );
        },
      ),
    );
  }

  Future<void> _pickAndUploadFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.single.path == null) return;

    final file = result.files.single;
    
    if (!mounted) return;
    
    final vault = context.read<VaultService>();
    
    setState(() => _isLoadingDocs = true);
    final uploadResult = await vault.uploadDocument(
      filePath: file.path!,
      fileName: file.name,
      transactionId: widget.transaction.id,
    );

    if (!mounted) return;
    
    uploadResult.fold(
      (failure) {
        setState(() => _isLoadingDocs = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: ${failure.message}')),
        );
      },
      (_) {
        _fetchAttachedDocs();
      },
    );
  }
}

class _VaultDocPicker extends StatefulWidget {
  const _VaultDocPicker({required this.onDocSelected});
  final void Function(VaultDocument) onDocSelected;

  @override
  State<_VaultDocPicker> createState() => _VaultDocPickerState();
}

class _VaultDocPickerState extends State<_VaultDocPicker> {
  String _search = '';
  List<VaultDocument> _docs = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    final vault = context.read<VaultService>();
    // We fetch root documents or search
    await vault.fetchDocuments(search: _search.isEmpty ? null : _search);
    if (mounted) {
      setState(() {
        _docs = vault.documents.where((d) => !d.isFolder).toList();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Link from Vault'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(
                hintText: 'Search documents...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (val) {
                setState(() => _search = val);
                _fetch();
              },
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: CircularProgressIndicator.adaptive())
            else if (_docs.isEmpty)
              const Center(child: Text('No documents found'))
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _docs.length,
                  itemBuilder: (context, index) {
                    final doc = _docs[index];
                    return ListTile(
                      leading: const Icon(Icons.insert_drive_file_outlined),
                      title: Text(doc.filename),
                      subtitle: Text(doc.fileType),
                      onTap: () {
                        widget.onDocSelected(doc);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      ],
    );
  }
}
