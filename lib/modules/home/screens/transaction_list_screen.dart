import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:mobile_app/core/config/app_config.dart';
import 'package:mobile_app/modules/auth/services/auth_service.dart';
import 'package:mobile_app/core/theme/app_theme.dart';
import 'package:mobile_app/modules/home/services/categories_service.dart';
import 'package:mobile_app/modules/home/models/transaction_category.dart';
import 'package:mobile_app/modules/home/services/dashboard_service.dart';

class TransactionListScreen extends StatefulWidget {
  const TransactionListScreen({super.key});

  @override
  State<TransactionListScreen> createState() => _TransactionListScreenState();
}

class _TransactionListScreenState extends State<TransactionListScreen> {
  final List<dynamic> _transactions = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _page = 1;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchTransactions();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CategoriesService>().fetchCategories();
    });
    
    _scrollController.addListener(() {
      if (_scrollController.position.pixels == _scrollController.position.maxScrollExtent) {
        _fetchTransactions();
      }
    });
  }

  Future<void> _fetchTransactions({bool reset = false}) async {
    if (_isLoading || (!reset && !_hasMore)) return;
    
    setState(() {
      _isLoading = true;
      if (reset) {
        _page = 1;
        _hasMore = true;
      }
    });

    final config = context.read<AppConfig>();
    final auth = context.read<AuthService>();
    final url = Uri.parse('${config.backendUrl}/api/v1/mobile/transactions').replace(queryParameters: {
      'page': _page.toString(),
      'page_size': '20',
    });

    try {
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer ${auth.accessToken}',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List items = data['items'];
        
        // Filter out hidden transactions
        final List newItems = items.where((item) => item['is_hidden'] != true).toList();
        
        final nextPage = data['next_page'];

        setState(() {
          if (reset) _transactions.clear();
          _transactions.addAll(newItems);
          _page++;
          _hasMore = nextPage != null;
        });
      }
    } catch (e) {
      debugPrint("Error fetching transactions: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
     final theme = Theme.of(context);
     return Scaffold(
       appBar: AppBar(title: const Text("Transactions")),
       body: RefreshIndicator(
         onRefresh: () => _fetchTransactions(reset: true),
         child: ListView.builder(
           physics: const AlwaysScrollableScrollPhysics(),
           controller: _scrollController,
           itemCount: _transactions.length + (_hasMore ? 1 : 0),
           itemBuilder: (context, index) {
             if (index == _transactions.length) {
               return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
             }
             
             final txn = _transactions[index];
             final amount = (txn['amount'] as num).toDouble();
             final date = DateTime.parse(txn['date']).toLocal();
             final category = txn['category'];
             
             return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.dividerColor),
                ),
                child: ListTile(
                  onTap: () => _showEditCategoryDialog(context, txn),
                  leading: Consumer<CategoriesService>(
                    builder: (context, catService, _) {
                      final String catName = category as String;
                      // Find category case-insensitive or exact
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
                        child: Text(
                          catName.isNotEmpty ? catName[0].toUpperCase() : '?',
                          style: TextStyle(color: theme.primaryColor, fontWeight: FontWeight.bold),
                        ),
                      );
                    },
                  ),
                  title: Text(txn['description'], maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${DateFormat('MMM d').format(date)} • ${txn['account_owner_name'] != null ? "${txn['account_owner_name']} - " : ""}${txn['account_name'] ?? 'Account'}',
                          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(Icons.edit, size: 12, color: theme.disabledColor),
                    ],
                  ),
                  trailing: Consumer<DashboardService>(
                    builder: (context, dashboard, _) {
                      return Text(
                        NumberFormat.currency(symbol: dashboard.currencySymbol, decimalDigits: 0).format(amount / dashboard.maskingFactor),
                        style: TextStyle(
                          color: amount < 0 ? AppTheme.danger : AppTheme.success,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    }
                  ),
                ),
             );
           },
         ),
       ),
       floatingActionButton: FloatingActionButton(
         child: const Icon(Icons.add),
         onPressed: () {
           // Navigate to add transaction
           Navigator.push(context, MaterialPageRoute(builder: (_) => const AddTransactionScreen()));
         },
       ),
     );
  }
  void _showEditCategoryDialog(BuildContext context, dynamic txn) {
     showModalBottomSheet(
       context: context,
       isScrollControlled: true,
       builder: (context) => _EditCategorySheet(txn: txn),
     ).then((updated) {
       if (updated == true) {
         setState(() {
            _page = 1;
            _transactions.clear();
            _hasMore = true;
         });
         _fetchTransactions();
       }
     });
   }
}

class _EditCategorySheet extends StatefulWidget {
  final dynamic txn;
  const _EditCategorySheet({required this.txn});

  @override
  State<_EditCategorySheet> createState() => _EditCategorySheetState();
}

class _EditCategorySheetState extends State<_EditCategorySheet> {
  late String _selectedCategory;
  bool _createRule = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.txn['category'];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CategoriesService>().fetchCategories();
    });
  }

  @override
  Widget build(BuildContext context) {
    final categoriesService = context.watch<CategoriesService>();
    final theme = Theme.of(context);
    
    // Fallback if categories fail to load or are empty
    final List<String> categories = categoriesService.categories.isNotEmpty 
        ? categoriesService.categories.map<String>((c) => c.name).toList()
        : <String>{'Food', 'Transport', 'Utilities', 'Shopping', 'Entertainment', 'Health', 'Education', 'Other', _selectedCategory}
            .toList();

    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Categorize Transaction", style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(widget.txn['description'], style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey)),
          const SizedBox(height: 24),
          
          DropdownButtonFormField<String>(
            initialValue: categories.contains(_selectedCategory) ? _selectedCategory : null,
            decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
            items: categories.map<DropdownMenuItem<String>>((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: (v) => setState(() => _selectedCategory = v!),
          ),
          
          const SizedBox(height: 16),
          CheckboxListTile(
            value: _createRule,
            onChanged: (val) => setState(() => _createRule = val!),
            title: const Text("Apply to similar transactions"),
            subtitle: const Text("Create a rule for this description"),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : () async {
                 setState(() => _isLoading = true);
                 final success = await context.read<CategoriesService>().updateTransactionCategory(
                   widget.txn['id'], 
                   _selectedCategory,
                   createRule: _createRule,
                   keywords: [widget.txn['description']],
                 );
                 
                 if (mounted) {
                   setState(() => _isLoading = false);
                   if (success) {
                     Navigator.pop(context, true);
                   } else {
                     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to update")));
                   }
                 }
              },
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              child: _isLoading ? const CircularProgressIndicator() : const Text("Save"),
            ),
          )
        ],
      ),
    );
  }
}

class AddTransactionScreen extends StatefulWidget {
  const AddTransactionScreen({super.key});

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  
  String? _category; // Change to nullable to handle dynamic categories properly
  String? _selectedAccountId;
  bool _isExpense = true;
  bool _isLoading = false;
  List<dynamic> _accounts = [];

  final List<String> _categories = [
    'Food', 'Transport', 'Utilities', 'Shopping', 
    'Entertainment', 'Health', 'Education', 'Other'
  ];

  @override
  void initState() {
    super.initState();
    _fetchAccounts();
     WidgetsBinding.instance.addPostFrameCallback((_) {
       context.read<CategoriesService>().fetchCategories();
     });
  }

  Future<void> _fetchAccounts() async {
    final config = context.read<AppConfig>();
    final auth = context.read<AuthService>();
    try {
      final response = await http.get(
        Uri.parse('${config.backendUrl}/api/v1/finance/accounts'),
        headers: {'Authorization': 'Bearer ${auth.accessToken}'},
      );
      if (response.statusCode == 200) {
        setState(() {
          _accounts = jsonDecode(response.body);
          if (_accounts.isNotEmpty) {
            _selectedAccountId = _accounts[0]['id'];
          }
        });
      }
    } catch (e) {
      debugPrint("Error fetching accounts: $e");
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _selectedAccountId == null) return;
    
    setState(() => _isLoading = true);
    
    final config = context.read<AppConfig>();
    final auth = context.read<AuthService>();
    
    try {
      // Use standard transaction creation endpoint (if available) or mobile specific one.
      // Assuming we have POST /api/v1/finance/transactions or similar.
      // For now, let's assume we need to create a mobile endpoint for this or use existing.
      // Let's create a specific mobile endpoint for "add expense" to keep things clean.
      
      final amount = double.parse(_amountCtrl.text);
      final finalAmount = _isExpense ? -amount : amount;

      final response = await http.post(
        Uri.parse('${config.backendUrl}/api/v1/mobile/transactions'),
        headers: {
          'Authorization': 'Bearer ${auth.accessToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'account_id': _selectedAccountId,
          'amount': finalAmount,
          'description': _descCtrl.text,
          'category': _category,
          'date': DateTime.now().toUtc().toIso8601String(),
        }),
      );

      if (response.statusCode == 200) {
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transaction Added')));
           Navigator.pop(context, true); // Return true to trigger refresh
        }
      } else {
        throw Exception('Failed to add transaction: ${response.body}');
      }
    } catch (e) {
       if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.danger));
       }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
     final theme = Theme.of(context);
     return Scaffold(
       appBar: AppBar(title: const Text("Add Transaction")),
       body: _accounts.isEmpty 
           ? const Center(child: CircularProgressIndicator())
           : Form(
         key: _formKey,
         child: ListView(
           padding: const EdgeInsets.all(16),
           children: [
             // Type Toggle
             Row(
               children: [
                 Expanded(
                   child: ChoiceChip(
                     label: const Center(child: Text("Expense")),
                     selected: _isExpense,
                     selectedColor: AppTheme.danger.withOpacity(0.2),
                     labelStyle: TextStyle(color: _isExpense ? AppTheme.danger : theme.colorScheme.onSurface),
                     onSelected: (v) => setState(() => _isExpense = true),
                   ),
                 ),
                 const SizedBox(width: 16),
                 Expanded(
                   child: ChoiceChip(
                     label: const Center(child: Text("Income")),
                     selected: !_isExpense,
                     selectedColor: AppTheme.success.withOpacity(0.2),
                     labelStyle: TextStyle(color: !_isExpense ? AppTheme.success : theme.colorScheme.onSurface),
                     onSelected: (v) => setState(() => _isExpense = false),
                   ),
                 ),
               ],
             ),
             const SizedBox(height: 24),
             
             DropdownButtonFormField<String>(
               initialValue: _selectedAccountId,
               decoration: const InputDecoration(labelText: 'Account'),
               items: _accounts.map<DropdownMenuItem<String>>((acc) {
                 return DropdownMenuItem(
                   value: acc['id'],
                   child: Text(acc['name']),
                 );
               }).toList(),
               onChanged: (v) => setState(() => _selectedAccountId = v),
             ),
             const SizedBox(height: 16),
             
              TextFormField(
                controller: _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Amount', prefixText: '${context.read<DashboardService>().currencySymbol} '),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
             const SizedBox(height: 16),
             
              Consumer<CategoriesService>(
                builder: (context, catService, _) {
                  final items = catService.categories.isNotEmpty
                      ? catService.categories.map((c) => DropdownMenuItem(
                          value: c.name,
                          child: Row(children: [
                            Text(c.icon ?? '', style: const TextStyle(fontSize: 16)),
                            const SizedBox(width: 8),
                            Text(c.name)
                          ])
                        )).toList()
                      : _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList();
                  
                  // Ensure current _category is valid for the list
                  final isValid = items.any((item) => item.value == _category);
                  final dropdownValue = isValid ? _category : (items.isNotEmpty ? items.first.value : null);

                  return DropdownButtonFormField<String>(
                    initialValue: dropdownValue,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: items,
                    onChanged: (v) => setState(() => _category = v),
                    validator: (v) => v == null ? 'Required' : null,
                  );
                },
              ),
             const SizedBox(height: 16),

             TextFormField(
               controller: _descCtrl,
               decoration: const InputDecoration(labelText: 'Description'),
               validator: (v) => v!.isEmpty ? 'Required' : null,
             ),
             const SizedBox(height: 32),
             
             SizedBox(
               width: double.infinity,
               child: ElevatedButton(
                 onPressed: _isLoading ? null : _submit,
                 style: ElevatedButton.styleFrom(
                   backgroundColor: _isExpense ? AppTheme.danger : AppTheme.success, 
                 ),
                 child: _isLoading 
                     ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                     : const Text('Save Transaction'),
               ),
             )
           ],
         ),
       ),
     );
  }
}
