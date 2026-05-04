import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:mobile_app/core/config/app_config.dart';
import 'package:mobile_app/core/theme/app_theme.dart';
import 'package:mobile_app/core/widgets/app_shell.dart';
import 'package:mobile_app/core/widgets/searchable_category_picker.dart';
import 'package:mobile_app/core/widgets/searchable_picker.dart';
import 'package:mobile_app/core/widgets/transaction_settings_sheet.dart';
import 'package:mobile_app/modules/auth/services/auth_service.dart';
import 'package:mobile_app/modules/home/models/dashboard_data.dart';
import 'package:mobile_app/modules/home/models/transaction_category.dart';
import 'package:mobile_app/modules/home/screens/transaction_detail_screen.dart';
import 'package:mobile_app/modules/home/services/categories_service.dart';
import 'package:mobile_app/modules/home/services/dashboard_service.dart';
import 'package:provider/provider.dart';

class ExpensesTab extends StatefulWidget {
  const ExpensesTab({super.key});

  @override
  State<ExpensesTab> createState() => _ExpensesTabState();
}

class _ExpensesTabState extends State<ExpensesTab> {
  final List<RecentTransaction> _transactions = [];
  final Set<String> _transactionIds = {};
  bool _isLoading = false;
  bool _hasMore = true;
  int _page = 1;
  final ScrollController _scrollController = ScrollController();

  String? _selectedCategoryId;
  String? _selectedAccountId;
  String _searchQuery = '';
  List<dynamic> _accounts = [];

  String? _lastMemberId;

  @override
  void initState() {
    super.initState();
    _fetchAccounts();
    // Initial fetch handled by build's check or explicitly here
    _fetchTransactions(reset: true);
    
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        _fetchTransactions();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchAccounts() async {
    final dashboard = context.read<DashboardService>();
    final result = await dashboard.fetchAccounts();
    result.fold(
      (failure) => debugPrint('Error fetching accounts: ${failure.message}'),
      (accounts) {
        if (mounted) {
          setState(() => _accounts = accounts);
        }
      },
    );
  }

  Future<void> _fetchTransactions({bool reset = false}) async {
    if (_isLoading || (!reset && !_hasMore)) return;

    if (reset) {
      setState(() {
        _page = 1;
        _hasMore = true;
      });
    }

    setState(() => _isLoading = true);

    final config = context.read<AppConfig>();
    final auth = context.read<AuthService>();
    final dashboard = context.read<DashboardService>();

    final url = Uri.parse('${config.backendUrl}/api/v1/mobile/transactions')
        .replace(
      queryParameters: {
        'page': _page.toString(),
        'page_size': '20',
        if (dashboard.selectedMemberId != null)
          'member_id': dashboard.selectedMemberId,
        if (_selectedCategoryId != null) 'category': _selectedCategoryId,
        if (_selectedAccountId != null) 'account_id': _selectedAccountId,
        if (_searchQuery.isNotEmpty) 'search': _searchQuery,
      },
    );

    try {
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer ${auth.accessToken}'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final List<RecentTransaction> items = (data['data'] as List<dynamic>? ?? [])
            .map((i) => RecentTransaction.fromJson(i as Map<String, dynamic>))
            .where((t) => !t.isHidden)
            .toList();
        final dynamic nextPage = data['next_page'];

        if (mounted) {
          setState(() {
            if (reset) {
              _transactions.clear();
              _transactionIds.clear();
            }
            
            for (final item in items) {
              // Composite key for content-based deduplication (last line of defense)
              final contentKey = '${item.amount}_${item.date.day}_${item.date.month}_${item.date.year}_${item.description.trim()}';
              
              if (!_transactionIds.contains(item.id) && !_transactionIds.contains(contentKey)) {
                _transactions.add(item);
                _transactionIds.add(item.id);
                _transactionIds.add(contentKey);
              }
            }
            
            _hasMore = nextPage != null;
            _page++;
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching transactions: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = context.watch<DashboardService>();
    final categories = context.watch<CategoriesService>().categories;

    // Auto-refresh when global filters change
    if (_lastMemberId != dashboard.selectedMemberId) {
      _lastMemberId = dashboard.selectedMemberId;
      Future.microtask(() => _fetchTransactions(reset: true));
    }

    return Column(
      children: [
        _buildSearchBar(dashboard, categories),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await dashboard.refresh();
              await _fetchTransactions(reset: true);
            },
            child: _transactions.isEmpty && !_isLoading
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _transactions.length + (_hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _transactions.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final txn = _transactions[index];
                      final prevTxn = index > 0 ? _transactions[index - 1] : null;
                      final isNewDay = prevTxn == null || 
                          txn.date.year != prevTxn.date.year ||
                          txn.date.month != prevTxn.date.month ||
                          txn.date.day != prevTxn.date.day;

                      if (isNewDay) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildDateHeader(txn.date),
                            _buildTransactionItem(txn),
                          ],
                        );
                      }
                      return _buildTransactionItem(txn);
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar(DashboardService dashboard, List<dynamic> categories) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: theme.cardColor.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: TextField(
                onChanged: (val) {
                  setState(() => _searchQuery = val);
                  _fetchTransactions(reset: true);
                },
                decoration: InputDecoration(
                  hintText: 'Search transactions...',
                  hintStyle: TextStyle(fontSize: 13, color: theme.disabledColor),
                  prefixIcon: Icon(Icons.search, size: 18, color: theme.disabledColor),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 11),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _FilterIconButton(
            icon: Icons.category_outlined,
            isActive: _selectedCategoryId != null,
            onTap: () => _showCategoryPicker(categories),
          ),
          const SizedBox(width: 4),
          _FilterIconButton(
            icon: Icons.account_balance_outlined,
            isActive: _selectedAccountId != null,
            onTap: _showAccountPicker(),
          ),
          if (_selectedCategoryId != null || _selectedAccountId != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () {
                setState(() {
                  _selectedCategoryId = null;
                  _selectedAccountId = null;
                });
                _fetchTransactions(reset: true);
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.filter_list_off, size: 20, color: AppTheme.danger),
              ),
            ),
          ],
        ],
      ),
    );
  }



  void _showCategoryPicker(List<dynamic> categories) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        builder: (_, controller) => Column(
          children: [
            Expanded(
              child: SearchableCategoryPicker(
                categories: [
                  TransactionCategory(id: 'all', name: 'All Categories', type: 'expense', icon: '📁'),
                  ...categories.cast<TransactionCategory>(),
                ],
                selected: _selectedCategoryId ?? 'All Categories',
                onSelected: (val) {
                  if (val == 'All Categories') {
                    setState(() => _selectedCategoryId = null);
                  } else {
                    // Extract leaf name if it's a hierarchy
                    final leaf = val.contains(' › ') ? val.split(' › ').last : val;
                    setState(() => _selectedCategoryId = leaf);
                  }
                  _fetchTransactions(reset: true);
                  Navigator.pop(context);
                },
                scrollController: controller,
              ),
            ),
          ],
        ),
      ),
    );
  }

  VoidCallback _showAccountPicker() {
    return () {
      final List<dynamic> items = [
        {'id': 'all', 'name': 'All Accounts'},
        ..._accounts,
      ];

      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => SearchablePickerModal(
          title: 'Select Account',
          items: items,
          labelMapper: (a) => (a as Map<String, dynamic>)['name'] as String,
          onSelected: (val) {
            final account = val as Map<String, dynamic>;
            setState(() => _selectedAccountId = account['id'] == 'all' ? null : account['id'] as String);
            _fetchTransactions(reset: true);
          },
        ),
      );
    };
  }

  Widget _buildDateHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final itemDate = DateTime(date.year, date.month, date.day);

    String label;
    if (itemDate == today) {
      label = 'Today';
    } else if (itemDate == yesterday) {
      label = 'Yesterday';
    } else {
      label = DateFormat('EEEE, d MMMM yyyy').format(date);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
        ),
      ),
    );
  }

  Widget _buildTransactionItem(RecentTransaction txn) {
    final dashboard = context.read<DashboardService>();
    final isNegative = txn.amount < Decimal.zero;
    final currency = dashboard.currencySymbol;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
      ),
      child: ListTile(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => AppShell(
              body: TransactionDetailScreen(transaction: txn),
            ),
          ),
        ),
        onLongPress: () => TransactionSettingsSheet.show(context, txn),
        leading: CircleAvatar(
          backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
          child: Builder(
            builder: (context) {
              final icon = txn.categoryIcon ??
                  context.read<CategoriesService>().getIconForCategory(
                    txn.category,
                  );
              if (icon != null && icon.isNotEmpty) {
                return Text(icon, style: const TextStyle(fontSize: 18));
              }
              return Text(
                txn.category.isNotEmpty ? txn.category[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              );
            },
          ),
        ),
        title: Text(
          txn.description,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Row(
          children: [
            if (txn.hasDocuments) ...[
              const Icon(Icons.attach_file, size: 12, color: AppTheme.primary),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                '${txn.category} • ${txn.accountName ?? 'Unknown'} • ${txn.formattedDate}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
          ],
        ),
        trailing: Text(
          '$currency${(txn.amount.abs().toDouble() / dashboard.maskingFactor).toStringAsFixed(0)}',
          style: TextStyle(
            color: isNegative ? AppTheme.danger : AppTheme.success,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          const Text('No transactions found', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          const Text('Try adjusting your filters', style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }
}

class _FilterIconButton extends StatelessWidget {
  const _FilterIconButton({
    required this.icon,
    required this.onTap,
    this.isActive = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: isActive ? AppTheme.primary.withValues(alpha: 0.1) : theme.cardColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? AppTheme.primary : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: IconButton(
        icon: Stack(
          children: [
            Icon(icon, size: 20, color: isActive ? AppTheme.primary : Colors.grey),
            if (isActive)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppTheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
