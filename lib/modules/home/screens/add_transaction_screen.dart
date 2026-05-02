import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:mobile_app/core/config/app_config.dart';
import 'package:mobile_app/modules/auth/services/auth_service.dart';
import 'package:mobile_app/core/theme/app_theme.dart';
import 'package:mobile_app/modules/home/services/categories_service.dart';
import 'package:mobile_app/modules/home/services/dashboard_service.dart';

class AddTransactionScreen extends StatefulWidget {
  const AddTransactionScreen({super.key});

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  String? _category;
  String? _selectedAccountId;
  bool _isExpense = true;
  bool _isLoading = false;
  List<dynamic> _accounts = [];

  final List<String> _categories = [
    'Food',
    'Transport',
    'Utilities',
    'Shopping',
    'Entertainment',
    'Health',
    'Education',
    'Other',
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
    if (!_formKey.currentState!.validate() || _selectedAccountId == null) {
      return;
    }

    setState(() => _isLoading = true);

    final config = context.read<AppConfig>();
    final auth = context.read<AuthService>();

    try {
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Transaction Added')));
          Navigator.pop(context, true);
        }
      } else {
        throw Exception('Failed to add transaction: ${response.body}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text("Add Transaction"), elevation: 0),
      body: _accounts.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text("Expense")),
                          selected: _isExpense,
                          selectedColor: AppTheme.danger.withValues(alpha: 0.2),
                          labelStyle: TextStyle(
                            color: _isExpense
                                ? AppTheme.danger
                                : theme.colorScheme.onSurface,
                          ),
                          onSelected: (v) => setState(() => _isExpense = true),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text("Income")),
                          selected: !_isExpense,
                          selectedColor: AppTheme.success.withValues(
                            alpha: 0.2,
                          ),
                          labelStyle: TextStyle(
                            color: !_isExpense
                                ? AppTheme.success
                                : theme.colorScheme.onSurface,
                          ),
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
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Amount',
                      prefixText:
                          '${context.read<DashboardService>().currencySymbol} ',
                    ),
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  Consumer<CategoriesService>(
                    builder: (context, catService, _) {
                      final items = catService.categories.isNotEmpty
                          ? catService.categories
                                .map(
                                  (c) => DropdownMenuItem(
                                    value: c.name,
                                    child: Row(
                                      children: [
                                        Text(
                                          c.icon ?? '',
                                          style: const TextStyle(fontSize: 16),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(c.name),
                                      ],
                                    ),
                                  ),
                                )
                                .toList()
                          : _categories
                                .map(
                                  (c) => DropdownMenuItem(
                                    value: c,
                                    child: Text(c),
                                  ),
                                )
                                .toList();

                      final isValid = items.any(
                        (item) => item.value == _category,
                      );
                      final dropdownValue = isValid
                          ? _category
                          : (items.isNotEmpty ? items.first.value : null);

                      return DropdownButtonFormField<String>(
                        initialValue: dropdownValue,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                        ),
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
                        backgroundColor: _isExpense
                            ? AppTheme.danger
                            : AppTheme.success,
                        minimumSize: const Size(0, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              'Save Transaction',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
