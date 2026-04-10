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
import 'package:mobile_app/modules/home/services/goals_service.dart';
import 'package:mobile_app/modules/home/screens/manage_group_transactions_screen.dart';

class ExpenseGroupDetailsScreen extends StatefulWidget {
  final dynamic group;
  const ExpenseGroupDetailsScreen({super.key, required this.group});

  @override
  State<ExpenseGroupDetailsScreen> createState() => _ExpenseGroupDetailsScreenState();
}

class _ExpenseGroupDetailsScreenState extends State<ExpenseGroupDetailsScreen> {
  late dynamic _group;
  List<dynamic> _transactions = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _group = widget.group;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CategoriesService>().fetchCategories();
      refreshData();
    });
  }

  Future<void> refreshData() async {
    await Future.wait([
      _fetchGroupDetails(),
      fetchExpenseGroupTransactions(),
    ]);
  }

  Future<void> _fetchGroupDetails() async {
    final config = context.read<AppConfig>();
    final auth = context.read<AuthService>();

    try {
      final response = await http.get(
        Uri.parse('${config.backendUrl}/api/v1/mobile/expense-groups/${_group['id']}'),
        headers: {'Authorization': 'Bearer ${auth.accessToken}'},
      );

      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _group = jsonDecode(response.body);
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching group: $e');
    }
  }

  Future<void> fetchExpenseGroupTransactions() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final config = context.read<AppConfig>();
    final auth = context.read<AuthService>();

    try {
      final url = Uri.parse('${config.backendUrl}/api/v1/mobile/transactions').replace(queryParameters: {
        'expense_group_id': widget.group['id'].toString(),
        'page_size': '100',
      });

      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer ${auth.accessToken}'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> items = data['data'] ?? [];
        
        final filtered = items.where((t) {
          final gid = t['expense_group_id']?.toString();
          return gid == _group['id'].toString();
        }).toList();

        if (mounted) {
          setState(() {
            _transactions = filtered;
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _error = 'Failed to load transactions: ${response.statusCode}';
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final group = _group;
    final budget = (group['budget'] ?? 0.0).toDouble();
    
    // Net spend: backend stores debits as negative, so negate to get positive spend
    double spent = 0;
    for (var txn in _transactions) {
      final amt = (txn['amount'] as num).toDouble();
      spent -= amt;
    }
    if (spent < 0) spent = 0;
    
    final progress = budget > 0 ? (spent / budget).clamp(0.0, 1.0) : 0.0;
    final isOverBudget = spent > budget && budget > 0;
    final isActive = group['is_active'] ?? true;
    final currency = context.read<DashboardService>().currencySymbol;
    final maskingFactor = context.read<DashboardService>().maskingFactor;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(group['name'] ?? 'Group Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _showEditGroupDialog(context),
            tooltip: 'Edit Group',
          ),
          PopupMenuButton<String>(
            onSelected: (val) {
              if (val == 'delete') _showDeleteConfirm(context);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, color: Colors.red, size: 20),
                    SizedBox(width: 8),
                    Text('Delete Group', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refreshData,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(group['icon'] ?? '📁', style: const TextStyle(fontSize: 40)),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                group['name'] ?? 'Unnamed Group',
                                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                              ),
                              if (group['description'] != null && group['description'].isNotEmpty)
                                Text(
                                  group['description'],
                                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    if (group['start_date'] != null || group['end_date'] != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today, size: 16, color: AppTheme.primary),
                            const SizedBox(width: 12),
                            Text(
                              '${group['start_date'] != null ? DateFormat('MMM d, yyyy').format(DateTime.parse(group['start_date'])) : "Start"} — ${group['end_date'] != null ? DateFormat('MMM d, yyyy').format(DateTime.parse(group['end_date'])) : "End"}',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: theme.colorScheme.onSurface),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 24),
                    _buildSummaryCard(theme, spent, budget, progress, isOverBudget, currency, maskingFactor),
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Linked Transactions',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '${_transactions.length} items',
                              style: TextStyle(color: theme.disabledColor, fontSize: 12),
                            ),
                          ],
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ManageGroupTransactionsScreen(group: _group),
                              ),
                            );
                            if (result == true) {
                              refreshData();
                            }
                          },
                          icon: const Icon(Icons.edit_note, size: 20),
                          label: const Text('Manage'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.primary,
                            backgroundColor: AppTheme.primary.withOpacity(0.1),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            if (_isLoading)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              SliverFillRemaining(child: Center(child: Text(_error!, style: const TextStyle(color: AppTheme.danger))))
            else if (_transactions.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.receipt_long_outlined, size: 64, color: theme.dividerColor),
                      const SizedBox(height: 16),
                      Text('No transactions linked to this group', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final txn = _transactions[index];
                    return _buildTransactionTile(context, txn, currency, maskingFactor);
                  },
                  childCount: _transactions.length,
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }

  void _showEditGroupDialog(BuildContext context) {
    final nameController = TextEditingController(text: _group['name']);
    final descriptionController = TextEditingController(text: _group['description']);
    final budgetController = TextEditingController(text: _group['budget']?.toString() ?? '');
    final iconController = TextEditingController(text: _group['icon'] ?? '📁');
    
    DateTime startDate = _group['start_date'] != null ? DateTime.parse(_group['start_date']) : DateTime.now();
    DateTime endDate = _group['end_date'] != null ? DateTime.parse(_group['end_date']) : DateTime.now().add(const Duration(days: 30));

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Expense Group'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: iconController, 
                  decoration: const InputDecoration(labelText: 'Icon (Emoji)'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24),
                ),
                const SizedBox(height: 16),
                TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Group Name')),
                const SizedBox(height: 8),
                TextField(controller: descriptionController, decoration: const InputDecoration(labelText: 'Description')),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: startDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2101),
                          );
                          if (picked != null) setDialogState(() => startDate = picked);
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Start Date', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            const SizedBox(height: 4),
                            Text(DateFormat('MMM d, yyyy').format(startDate)),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: endDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2101),
                          );
                          if (picked != null) setDialogState(() => endDate = picked);
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('End Date', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            const SizedBox(height: 4),
                            Text(DateFormat('MMM d, yyyy').format(endDate)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: budgetController, 
                  decoration: const InputDecoration(labelText: 'Budget', prefixText: '₹ '),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final service = context.read<GoalsService>();
                final success = await service.updateExpenseGroup(_group['id'].toString(), {
                  'name': nameController.text,
                  'description': descriptionController.text,
                  'icon': iconController.text,
                  'budget': double.tryParse(budgetController.text) ?? 0.0,
                  'start_date': startDate.toIso8601String(),
                  'end_date': endDate.toIso8601String(),
                });
                if (success && mounted) {
                  Navigator.pop(context);
                  refreshData();
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirm(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Group?'),
        content: const Text('All links will be removed. Transactions themselves won\'t be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final success = await context.read<GoalsService>().deleteExpenseGroup(_group['id'].toString());
              if (success && mounted) {
                Navigator.pop(context); // Close dialog
                Navigator.pop(context, true); // Go back to list
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
    ThemeData theme, 
    double spent, 
    double budget, 
    double progress, 
    bool isOverBudget, 
    String currency,
    double maskingFactor
  ) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [theme.colorScheme.surface, theme.colorScheme.surface.withOpacity(0.9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 8))
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Actual Spending', style: TextStyle(color: Colors.grey[600], fontSize: 13, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Text(
                      '$currency${(spent / maskingFactor).toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 28, 
                        fontWeight: FontWeight.w900,
                        color: isOverBudget ? AppTheme.danger : AppTheme.primary,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (budget > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Target Budget', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                      Text(
                        '$currency${(budget / maskingFactor).toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (budget > 0) ...[
            const SizedBox(height: 24),
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 16,
                    backgroundColor: Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation<Color>(isOverBudget ? AppTheme.danger : AppTheme.primary),
                  ),
                ),
                if (progress > 0.05)
                Positioned.fill(
                  child: Center(
                    child: Text(
                      '${(progress * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (isOverBudget)
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 14, color: AppTheme.danger),
                      const SizedBox(width: 4),
                      Text(
                        'Exceeded by $currency${((spent - budget) / maskingFactor).toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.danger),
                      ),
                    ],
                  )
                else
                  Text(
                    'Remaining: $currency${((budget - spent) / maskingFactor).toStringAsFixed(0)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[700], fontWeight: FontWeight.w500),
                  ),
                Text(
                  'Goal Balance',
                  style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.info_outline, size: 14, color: Colors.grey),
                const SizedBox(width: 8),
                Text('Set a budget to track progress', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTransactionTile(BuildContext context, dynamic txn, String currency, double maskingFactor) {
    final theme = Theme.of(context);
    final amount = (txn['amount'] as num).toDouble();
    final date = DateTime.parse(txn['date']).toLocal();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Consumer<CategoriesService>(
          builder: (context, catService, _) {
            final catName = (txn['category'] as String?) ?? 'Uncategorized';
            final matched = catService.categories
                .cast<TransactionCategory?>()
                .firstWhere(
                  (c) => c?.name.toLowerCase() == catName.toLowerCase(),
                  orElse: () => null,
                );
            
            if (matched?.icon != null) {
              return CircleAvatar(
                backgroundColor: theme.primaryColor.withOpacity(0.1),
                child: Text(matched!.icon!, style: const TextStyle(fontSize: 20)),
              );
            }
            
            return CircleAvatar(
              backgroundColor: theme.primaryColor.withOpacity(0.1),
              child: const Icon(Icons.receipt_long, color: AppTheme.primary),
            );
          },
        ),
        title: Text(
          txn['description'],
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Text(
          DateFormat('dd MMM yyyy, HH:mm').format(date),
          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
        ),
        trailing: Text(
          '$currency${(amount.abs() / maskingFactor).toStringAsFixed(1)}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: amount < 0 ? AppTheme.danger : AppTheme.success,
          ),
        ),
      ),
    );
  }
}
