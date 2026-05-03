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
    _fetchTransactions(reset: true);
    _fetchAccounts();
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
        final items = (data['data'] as List<dynamic>? ?? [])
            .map((i) => RecentTransaction.fromJson(i as Map<String, dynamic>))
            .where((t) => !t.isHidden)
            .toList();
        final dynamic nextPage = data['next_page'];

        if (mounted) {
          setState(() {
            if (reset) _transactions.clear();
            _transactions.addAll(items);
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
        _buildSearchBar(),
        _buildFilterBar(dashboard, categories),
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

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TextField(
        onChanged: (val) {
          setState(() => _searchQuery = val);
          // Debounce could be added, but for now just fetch on change
          _fetchTransactions(reset: true);
        },
        decoration: InputDecoration(
          hintText: 'Search transactions...',
          prefixIcon: const Icon(Icons.search, size: 20),
          filled: true,
          fillColor: Theme.of(context).cardColor.withValues(alpha: 0.5),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildFilterBar(DashboardService dashboard, List<dynamic> categories) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _FilterChip(
              label: dashboard.selectedMemberId != null
                  ? (dashboard.members.firstWhere(
                      (m) => (m as Map<String, dynamic>)['id'] == dashboard.selectedMemberId,
                      orElse: () => {'name': 'Member'}) as Map<String, dynamic>)['name'] as String
                  : 'Family',
              icon: Icons.people_outline,
              onTap: () => _showMemberPicker(dashboard),
              isActive: dashboard.selectedMemberId != null,
            ),
            const SizedBox(width: 8),
            _FilterChip(
              label: _selectedCategoryId ?? 'Category',
              icon: Icons.category_outlined,
              onTap: () => _showCategoryPicker(categories),
              isActive: _selectedCategoryId != null,
            ),
            const SizedBox(width: 8),
            _FilterChip(
              label: _selectedAccountId != null
                  ? ((_accounts.firstWhere(
                      (a) => (a as Map<String, dynamic>)['id'] == _selectedAccountId,
                      orElse: () => {'name': 'Account'}) as Map<String, dynamic>)['name'] as String)
                  : 'Account',
              icon: Icons.account_balance_outlined,
              onTap: _showAccountPicker(),
              isActive: _selectedAccountId != null,
            ),
            if (dashboard.selectedMemberId != null ||
                _selectedCategoryId != null ||
                _selectedAccountId != null) ...[
              const SizedBox(width: 12),
              VerticalDivider(
                width: 1,
                indent: 8,
                endIndent: 8,
                color: Theme.of(context).dividerColor,
              ),
              const SizedBox(width: 12),
              TextButton.icon(
                onPressed: () {
                  dashboard.setMember(null);
                  setState(() {
                    _selectedCategoryId = null;
                    _selectedAccountId = null;
                  });
                  _fetchTransactions(reset: true);
                },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Reset', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.danger,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showMemberPicker(DashboardService dashboard) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            title: const Text('Full Family'),
            selected: dashboard.selectedMemberId == null,
            onTap: () {
              dashboard.setMember(null);
              Navigator.pop(context);
              _fetchTransactions(reset: true);
            },
          ),
          const Divider(height: 1),
          ...dashboard.members.map((m) {
            final member = m as Map<String, dynamic>;
            final isSelected = dashboard.selectedMemberId == member['id'];
            return ListTile(
                title: Text(
                  member['name'] as String,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                selected: isSelected,
                trailing: isSelected ? const Icon(Icons.check, color: AppTheme.primary) : null,
                onTap: () {
                  dashboard.setMember(member['id'] as String?);
                  Navigator.pop(context);
                  _fetchTransactions(reset: true);
                },
              );
          }),
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

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isActive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.primary.withValues(alpha: 0.1) : theme.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? AppTheme.primary : theme.dividerColor.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isActive ? AppTheme.primary : Colors.grey),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: isActive ? AppTheme.primary : theme.textTheme.bodyMedium?.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
