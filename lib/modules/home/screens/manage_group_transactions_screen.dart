import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:mobile_app/core/config/app_config.dart';
import 'package:mobile_app/core/theme/app_theme.dart';
import 'package:mobile_app/modules/auth/services/auth_service.dart';
import 'package:mobile_app/modules/home/services/categories_service.dart';
import 'package:mobile_app/modules/home/models/transaction_category.dart';
import 'package:mobile_app/modules/home/services/dashboard_service.dart';

class ManageGroupTransactionsScreen extends StatefulWidget {
  final dynamic group;
  const ManageGroupTransactionsScreen({super.key, required this.group});

  @override
  State<ManageGroupTransactionsScreen> createState() => _ManageGroupTransactionsScreenState();
}

class _ManageGroupTransactionsScreenState extends State<ManageGroupTransactionsScreen> {
  List<dynamic> _allTransactions = [];
  Set<String> _selectedIds = {};
  Set<String> _initialSelectedIds = {};
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  String _searchQuery = '';
  String? _filterCategory;
  String? _filterAccount;
  bool _showLinkedOnly = false;

  @override
  void initState() {
    super.initState();
    _fetchEligibleTransactions();
  }

  Future<void> _fetchEligibleTransactions() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final config = context.read<AppConfig>();
    final auth = context.read<AuthService>();

    try {
      final queryParams = {
        'page_size': '500',
      };

      if (widget.group['start_date'] != null) {
        queryParams['start_date'] = widget.group['start_date'];
      }
      if (widget.group['end_date'] != null) {
        queryParams['end_date'] = widget.group['end_date'];
      }

      final url = Uri.parse('${config.backendUrl}/api/v1/mobile/transactions').replace(queryParameters: queryParams);

      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer ${auth.accessToken}'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> items = data['data'];
        
        final Set<String> selected = {};
        for (var item in items) {
          final gid = item['expense_group_id']?.toString();
          if (gid == widget.group['id'].toString()) {
            selected.add(item['id'].toString());
          }
        }

        setState(() {
          _allTransactions = items;
          _selectedIds = selected;
          _initialSelectedIds = Set.from(selected);
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load transactions';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);

    final config = context.read<AppConfig>();
    final auth = context.read<AuthService>();
    final groupId = widget.group['id'].toString();

    try {
      final toLink = _selectedIds.difference(_initialSelectedIds).toList();
      final toUnlink = _initialSelectedIds.difference(_selectedIds).toList();

      if (toLink.isNotEmpty) {
        await http.post(
          Uri.parse('${config.backendUrl}/api/v1/mobile/expense-groups/$groupId/link'),
          headers: {
            'Authorization': 'Bearer ${auth.accessToken}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'transaction_ids': toLink}),
        );
      }

      if (toUnlink.isNotEmpty) {
        await http.post(
          Uri.parse('${config.backendUrl}/api/v1/mobile/expense-groups/$groupId/unlink'),
          headers: {
            'Authorization': 'Bearer ${auth.accessToken}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'transaction_ids': toUnlink}),
        );
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = context.read<DashboardService>().currencySymbol;
    final maskingFactor = context.read<DashboardService>().maskingFactor;

    final categories = _allTransactions
        .map((t) => t['category']?.toString() ?? 'Uncategorized')
        .toSet()
        .toList()
      ..sort();

    final accounts = _allTransactions
        .map((t) => t['account_name']?.toString() ?? 'Unknown Account')
        .toSet()
        .toList()
      ..sort();

    final filtered = _allTransactions.where((txn) {
      if (_searchQuery.isNotEmpty) {
        final desc = (txn['description'] ?? '').toString().toLowerCase();
        final acc = (txn['account_name'] ?? '').toString().toLowerCase();
        if (!desc.contains(_searchQuery.toLowerCase()) && !acc.contains(_searchQuery.toLowerCase())) {
          return false;
        }
      }

      if (_filterCategory != null && txn['category'] != _filterCategory) return false;
      if (_filterAccount != null && txn['account_name'] != _filterAccount) return false;
      if (_showLinkedOnly && !_selectedIds.contains(txn['id'].toString())) return false;

      return true;
    }).toList();

    final pinned = filtered.where((t) => _selectedIds.contains(t['id'].toString())).toList();
    final available = filtered.where((t) => !_selectedIds.contains(t['id'].toString())).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Link Transactions'),
        actions: [
          if (!_isLoading)
            IconButton(
              onPressed: _isSaving ? null : _saveChanges,
              icon: _isSaving 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check_circle_outline, color: AppTheme.primary),
              tooltip: 'Save linkage',
            ),
        ],
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildAdvancedFilters(theme, categories, accounts),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Showing transactions from ${widget.group['start_date'] != null ? DateFormat('MMM d').format(DateTime.parse(widget.group['start_date'])) : "..."} to ${widget.group['end_date'] != null ? DateFormat('MMM d').format(DateTime.parse(widget.group['end_date'])) : "..."}',
                          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: ListView(
                    children: [
                      if (pinned.isNotEmpty) ...[
                        _buildSectionHeader('SELECTED (${pinned.length})', AppTheme.primary),
                        ...pinned.map((txn) => _buildTxnTile(txn, currency, maskingFactor, true)),
                      ],
                      if (available.isNotEmpty) ...[
                        _buildSectionHeader('AVAILABLE', Colors.grey),
                        ...available.map((txn) => _buildTxnTile(txn, currency, maskingFactor, false)),
                      ],
                      if (pinned.isEmpty && available.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 80),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.search_off, size: 64, color: Colors.grey[300]),
                                const SizedBox(height: 16),
                                Text('No matching transactions', style: TextStyle(color: Colors.grey[600])),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildAdvancedFilters(ThemeData theme, List<String> categories, List<String> accounts) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          TextField(
            onChanged: (val) => setState(() => _searchQuery = val),
            decoration: InputDecoration(
              hintText: 'Search Description or account...',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('Pinned Only'),
                  selected: _showLinkedOnly,
                  onSelected: (val) => setState(() => _showLinkedOnly = val),
                ),
                const SizedBox(width: 8),
                _buildFilterDropdown(
                  'Category',
                  _filterCategory,
                  categories,
                  (val) => setState(() => _filterCategory = val),
                ),
                const SizedBox(width: 8),
                _buildFilterDropdown(
                  'Account',
                  _filterAccount,
                  accounts,
                  (val) => setState(() => _filterAccount = val),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown(String label, String? current, List<String> items, Function(String?) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: current != null ? AppTheme.primary : Colors.transparent),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: current,
          hint: Text(label, style: const TextStyle(fontSize: 12)),
          onChanged: onChanged,
          items: [
            DropdownMenuItem(value: null, child: Text('All $label', style: const TextStyle(fontSize: 12))),
            ...items.map((i) => DropdownMenuItem(value: i, child: Text(i, style: const TextStyle(fontSize: 12)))),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color, letterSpacing: 1),
      ),
    );
  }

  Widget _buildTxnTile(dynamic txn, String currency, double maskingFactor, bool isSelected) {
    final theme = Theme.of(context);
    final id = txn['id'].toString();
    final amount = (txn['amount'] as num).toDouble();
    final date = DateTime.parse(txn['date']).toLocal();

    return CheckboxListTile(
      value: isSelected,
      onChanged: (val) {
        setState(() {
          if (val == true) {
            _selectedIds.add(id);
          } else {
            _selectedIds.remove(id);
          }
        });
      },
      title: Text(
        txn['description'] ?? 'Unnamed',
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontSize: 14,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              '${DateFormat('MMM d').format(date)} • ${txn['account_name']}',
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '$currency${(amount.abs() / maskingFactor).toStringAsFixed(0)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: amount < 0 ? AppTheme.danger : AppTheme.success,
            ),
          ),
        ],
      ),
      secondary: Consumer<CategoriesService>(
        builder: (context, catService, _) {
          final catName = (txn['category'] as String?) ?? 'Uncategorized';
          final matched = catService.categories
              .cast<TransactionCategory?>()
              .firstWhere(
                (c) => c?.name.toLowerCase() == catName.toLowerCase(),
                orElse: () => null,
              );
          return CircleAvatar(
            radius: 18,
            backgroundColor: (isSelected ? AppTheme.primary : Colors.grey).withOpacity(0.05),
            child: Text(matched?.icon ?? '🏷️', style: const TextStyle(fontSize: 16)),
          );
        },
      ),
      controlAffinity: ListTileControlAffinity.leading,
      activeColor: AppTheme.primary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
    );
  }
}
