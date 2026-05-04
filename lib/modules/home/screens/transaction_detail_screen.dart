import 'package:file_picker/file_picker.dart';
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

  final List<Map<String, dynamic>> _vendorTransactions = [];
  final Set<String> _vendorTransactionIds = {};
  int _vendorSkip = 0;
  bool _isLoadingMoreVendorTxns = false;
  bool _hasMoreVendorTxns = true;
  final ScrollController _scrollController = ScrollController();
  
  // Reuse formatters to avoid expensive re-instantiation in build loop
  static final DateFormat _dayMonthFormat = DateFormat('dd MMM');
  late final NumberFormat _currencyFormat;
  late final NumberFormat _currencyFormatNoDecimals;

  @override
  void initState() {
    super.initState();
    _fetchData();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
        _fetchVendorStats(loadMore: true);
      }
    });

    // Initialize formatters once
    final dashboard = context.read<DashboardService>();
    _currencyFormat = NumberFormat.currency(
      symbol: dashboard.currencySymbol,
      decimalDigits: 2,
    );
    _currencyFormatNoDecimals = NumberFormat.currency(
      symbol: dashboard.currencySymbol,
      decimalDigits: 0,
    );
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
        _vendorTransactionIds.clear();
      });
    }
    
    final dashboard = context.read<DashboardService>();
    final result = await dashboard.fetchVendorStats(recipient, skip: _vendorSkip, limit: 10);
    
    if (mounted) {
      result.fold(
        (failure) => debugPrint('Failed to fetch vendor stats: ${failure.message}'),
        (stats) {
          setState(() {
            if (!loadMore) {
              _vendorStats = stats;
            }
            final newTxns = (stats['recent_transactions'] as List<dynamic>?) ?? [];
            
            // Pre-format items for smooth scrolling
            final formattedItems = newTxns.map((t) {
              final txn = t as Map<String, dynamic>;
              final date = DateTime.parse(txn['date'] as String);
              return {
                ...txn,
                '_displayAmount': _currencyFormatNoDecimals.format((txn['amount'] as num).abs() / dashboard.maskingFactor),
                '_displayDate': _dayMonthFormat.format(date),
              };
            }).toList();

            for (final item in formattedItems) {
              final id = item['id'] as String;
              if (!_vendorTransactionIds.contains(id)) {
                _vendorTransactions.add(item);
                _vendorTransactionIds.add(id);
              }
            }
            
            _vendorSkip += newTxns.length;
            _hasMoreVendorTxns = newTxns.length == 10;
            _isLoadingStats = false;
            _isLoadingMoreVendorTxns = false;
          });
        },
      );
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
    // Only listen to maskingFactor to avoid redundant rebuilds from unrelated dashboard updates
    final maskingFactor = context.select<DashboardService, double>((s) => s.maskingFactor);
    final theme = Theme.of(context);

    final amount = transaction.amount.toDouble() / maskingFactor;
    final formattedAmount = _currencyFormat.format(amount);

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
              stretchModes: const [StretchMode.zoomBackground],
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
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          formattedAmount,
                          style: const TextStyle(
                            fontSize: 42,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: -1,
                          ),
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
                            Flexible(
                              child: Text(
                                transaction.category.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                ),
                                overflow: TextOverflow.ellipsis,
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
                  TransactionInfoCard(theme: theme, transaction: transaction),
                  const SizedBox(height: 32),
                  if (widget.transaction.recipient != null || widget.transaction.description.isNotEmpty) ...[
                    VendorInsightsSection(
                      transaction: widget.transaction,
                      vendorStats: _vendorStats,
                      isLoading: _isLoadingStats,
                      maskingFactor: maskingFactor,
                      currencyFormat: _currencyFormatNoDecimals,
                    ),
                    const SizedBox(height: 32),
                  ],
                  EvidenceSection(
                    isLoading: _isLoadingDocs,
                    documents: _attachedDocs,
                    onAddPressed: _showAddEvidenceDialog,
                    onDocPressed: _openDocument,
                    onDocDeleted: _detachDoc,
                  ),
                  const SizedBox(height: 32),
                  TransactionTimeline(transaction: transaction),
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
                      return VendorHistoryItem(
                        transaction: txn,
                        formattedAmount: txn['_displayAmount'] as String,
                        formattedDate: txn['_displayDate'] as String,
                        theme: theme,
                      );
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

  Widget _buildTrendInfo(String label, double amount, NumberFormat format, double maskingFactor) {
    return Column(
      crossAxisAlignment: label == 'Highest' ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1),
        ),
        Text(
          format.format(amount / maskingFactor),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
      ],
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

class VendorInsightsSection extends StatelessWidget {
  const VendorInsightsSection({
    required this.transaction,
    required this.vendorStats,
    required this.isLoading,
    required this.maskingFactor,
    required this.currencyFormat,
    super.key,
  });

  final RecentTransaction transaction;
  final Map<String, dynamic>? vendorStats;
  final bool isLoading;
  final double maskingFactor;
  final NumberFormat currencyFormat;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    if (vendorStats == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final stats = vendorStats!;
    final name = transaction.recipient ?? transaction.description;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'INSIGHTS FOR $name',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  color: Colors.grey,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: _buildStatItem('Lifetime Spend', (stats['total_spent'] as num?) ?? 0, currencyFormat, maskingFactor)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildStatItem('Visit Count', (stats['transaction_count'] as num?) ?? 0, null, 1.0)),
                ],
              ),
              const SizedBox(height: 24),
              // Simplified Lightweight Chart
              SizedBox(
                height: 80,
                child: _buildSimpleLightweightChart((stats['chart_data'] as List<dynamic>?) ?? [], maskingFactor, theme),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: _buildTrendInfo('Average', ((stats['average_transaction'] as num?) ?? 0).toDouble(), currencyFormat, maskingFactor)),
                  if (stats['total_invested'] != null && (stats['total_invested'] as num) > 0) ...[
                    const SizedBox(width: 16),
                    Expanded(child: _buildTrendInfo('Invested', ((stats['total_invested'] as num?) ?? 0).toDouble(), currencyFormat, maskingFactor)),
                  ]
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, num value, NumberFormat? format, double maskingFactor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1),
        ),
        const SizedBox(height: 4),
        Text(
          format != null ? format.format(value.toDouble() / maskingFactor) : value.toString(),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5),
        ),
      ],
    );
  }

  Widget _buildSimpleLightweightChart(List<dynamic> data, double maskingFactor, ThemeData theme) {
    if (data.isEmpty) return const Center(child: Text('No historical data', style: TextStyle(fontSize: 11, color: Colors.grey)));

    final maxVal = data.map((e) => ((e['amount'] as num?) ?? 0).toDouble()).reduce((a, b) => a > b ? a : b);
    if (maxVal == 0) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: data.map((e) {
        final val = ((e['amount'] as num?) ?? 0).toDouble();
        final ratio = val / maxVal;
        final monthStr = e['month'].toString().split('-').last;
        
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Expanded(
                  child: FractionallySizedBox(
                    heightFactor: ratio.clamp(0.05, 1.0),
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            AppTheme.primary,
                            AppTheme.primary.withValues(alpha: 0.6),
                          ],
                        ),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _getMonthName(monthStr),
                  style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  String _getMonthName(String month) {
    const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
    try {
      final idx = int.parse(month) - 1;
      if (idx >= 0 && idx < 12) return months[idx];
    } catch (_) {}
    return month;
  }


  Widget _buildTrendInfo(String label, double amount, NumberFormat format, double maskingFactor) {
    return Column(
      crossAxisAlignment: label == 'Highest' ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1),
        ),
        Text(
          format.format(amount / maskingFactor),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
      ],
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

class TransactionInfoCard extends StatelessWidget {
  const TransactionInfoCard({
    required this.transaction,
    required this.theme,
    super.key,
  });

  final RecentTransaction transaction;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
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
          _InfoRow(icon: Icons.description_outlined, label: 'DESCRIPTION', value: transaction.description),
          const _InfoDivider(),
          _InfoRow(icon: Icons.calendar_today_outlined, label: 'DATE & TIME', value: transaction.formattedDate),
          const _InfoDivider(),
          _InfoRow(icon: Icons.account_balance_wallet_outlined, label: 'FUND SOURCE', value: transaction.accountName ?? 'Manual Entry'),
          if (transaction.accountOwnerName != null) ...[
            const _InfoDivider(),
            _InfoRow(icon: Icons.person_outline, label: 'OWNED BY', value: transaction.accountOwnerName!),
          ],
          const _InfoDivider(),
          _InfoRow(
            icon: Icons.bolt_outlined,
            label: 'INGESTION',
            value: transaction.source?.toUpperCase() ?? 'DIRECT',
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
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
}

class _InfoDivider extends StatelessWidget {
  const _InfoDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Divider(height: 1, color: Colors.grey.withValues(alpha: 0.1)),
    );
  }
}

class VendorHistoryItem extends StatelessWidget {
  const VendorHistoryItem({
    required this.transaction,
    required this.formattedAmount,
    required this.formattedDate,
    required this.theme,
    super.key,
  });

  final Map<String, dynamic> transaction;
  final String formattedAmount;
  final String formattedDate;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final amount = (transaction['amount'] as num?) ?? 0;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
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
              formattedDate.toUpperCase(),
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
                  (transaction['description'] as String?) ?? 'No description',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (transaction['category'] != null)
                  Text(
                    (transaction['category'] as String).toUpperCase(),
                    style: TextStyle(fontSize: 9, color: Colors.grey.shade500, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  ),
              ],
            ),
          ),
          Text(
            formattedAmount,
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
}

class TransactionTimeline extends StatelessWidget {
  const TransactionTimeline({required this.transaction, super.key});
  final RecentTransaction transaction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Transaction Timeline',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        _TimelineItem(
          title: 'Detected',
          subtitle: 'Transaction recognized via ${transaction.source ?? 'manual entry'}',
          time: transaction.formattedDate,
          isFirst: true,
          isLast: false,
        ),
        _TimelineItem(
          title: 'Categorized',
          subtitle: 'Auto-assigned to ${transaction.category}',
          time: '',
          isFirst: false,
          isLast: false,
        ),
        _TimelineItem(
          title: 'Synced',
          subtitle: 'Successfully archived to cloud ledger',
          time: '',
          isFirst: false,
          isLast: true,
        ),
      ],
    );
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({
    required this.title,
    required this.subtitle,
    required this.time,
    required this.isFirst,
    required this.isLast,
  });

  final String title;
  final String subtitle;
  final String time;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
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
                  Expanded(
                    child: Text(
                      title, 
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (time.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(time, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
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
}

class EvidenceSection extends StatelessWidget {
  const EvidenceSection({
    required this.isLoading,
    required this.documents,
    required this.onAddPressed,
    required this.onDocPressed,
    required this.onDocDeleted,
    super.key,
  });

  final bool isLoading;
  final List<VaultDocument> documents;
  final VoidCallback onAddPressed;
  final Function(VaultDocument) onDocPressed;
  final Function(String) onDocDeleted;

  @override
  Widget build(BuildContext context) {
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
              onPressed: onAddPressed,
              icon: const Icon(Icons.add_circle_outline, color: AppTheme.primary),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (isLoading)
          const Center(child: CircularProgressIndicator.adaptive())
        else if (documents.isEmpty)
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
            itemCount: documents.length,
            itemBuilder: (context, index) {
              final doc = documents[index];
              return _DocCard(
                doc: doc,
                onPressed: () => onDocPressed(doc),
                onDeleted: () => onDocDeleted(doc.id),
              );
            },
          ),
      ],
    );
  }
}

class _DocCard extends StatelessWidget {
  const _DocCard({
    required this.doc,
    required this.onPressed,
    required this.onDeleted,
  });

  final VaultDocument doc;
  final VoidCallback onPressed;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onPressed,
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
                onPressed: onDeleted,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
          ],
        ),
      ),
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
}
