import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:mobile_app/core/theme/app_theme.dart';
import 'package:mobile_app/core/widgets/searchable_picker.dart';
import 'package:mobile_app/core/widgets/category_picker.dart';
import 'package:mobile_app/modules/home/models/unparsed_message.dart';
import 'package:mobile_app/modules/home/services/dashboard_service.dart';
import 'package:mobile_app/modules/home/services/categories_service.dart';
import 'package:decimal/decimal.dart';

class ForensicAnnotationForm extends StatefulWidget {
  final UnparsedMessage message;
  final VoidCallback onComplete;

  const ForensicAnnotationForm({
    super.key,
    required this.message,
    required this.onComplete,
  });

  @override
  State<ForensicAnnotationForm> createState() => _ForensicAnnotationFormState();
}

class _ForensicAnnotationFormState extends State<ForensicAnnotationForm> {
  late TextEditingController _amountController;
  late TextEditingController _descController;
  DateTime _date = DateTime.now();
  String _category = 'Uncategorized';
  String? _selectedAccountId;
  String? _selectedAccountName;
  bool _createRule = true;
  bool _isAIParsing = false;
  String _type = 'DEBIT'; // DEBIT or CREDIT

  // For highlighting AI changes
  bool _isAmountAI = false;
  bool _isDescAI = false;
  bool _isCategoryAI = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController();
    _descController = TextEditingController();
    _date = widget.message.receivedAt;

    // Pre-fetch categories
    context.read<CategoriesService>().fetchCategories();

    // Check if message content implies credit
    final contentLC = widget.message.content.toLowerCase();
    if (contentLC.contains('credited') || contentLC.contains('received')) {
      _type = 'CREDIT';
    }
  }

  void _runAIForensic() async {
    setState(() => _isAIParsing = true);
    final dashboard = context.read<DashboardService>();
    final result = await dashboard.aiForensicParse(widget.message.content);

    result.fold(
      (failure) {
        if (mounted) {
          setState(() {
            _isAIParsing = false;
            _errorMessage = failure.message;
          });
          Future.delayed(const Duration(seconds: 5), () {
            if (mounted) setState(() => _errorMessage = null);
          });
        }
      },
      (data) {
        if (mounted) {
          setState(() {
            _amountController.text = (data['amount'] ?? '').toString();
            _descController.text = data['description'] ?? '';
            _category = data['category'] ?? 'Uncategorized';
            _type = data['type'] ?? _type;

            _isAmountAI = true;
            _isDescAI = true;
            _isCategoryAI = true;
            _isAIParsing = false;

            // Auto-select account if mask matches
            final mask = data['account_mask']?.toString();
            if (mask != null && mask.length >= 4) {
              final last4 = mask.substring(mask.length - 4);
              for (var acc in _accounts) {
                final accName = acc['name'].toString().toLowerCase();
                if (accName.contains(last4)) {
                  _selectedAccountId = acc['id'] as String;
                  _selectedAccountName = acc['name'] as String;
                  break;
                }
              }
            }
          });

          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              setState(() {
                _isAmountAI = false;
                _isDescAI = false;
                _isCategoryAI = false;
              });
            }
          });
        }
      },
    );
  }

  List<dynamic> _accounts = [];
  bool _isLoadingAccounts = true;

  void _loadAccounts() async {
    final dashboard = context.read<DashboardService>();
    final result = await dashboard.fetchAccounts();

    result.fold(
      (failure) => debugPrint('Error loading accounts: ${failure.message}'),
      (accs) {
        if (mounted) {
          setState(() {
            _accounts = accs;
            _isLoadingAccounts = false;
          });
        }
      },
    );
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null && picked != _date) {
      setState(() {
        _date = picked;
      });
    }
  }

  void _submit() async {
    if (_selectedAccountId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select an Account')));
      return;
    }

    final dashboard = context.read<DashboardService>();
    final result = await dashboard.finalizeTraining(
      messageId: widget.message.id,
      date: _date,
      description: _descController.text,
      amount: Decimal.tryParse(_amountController.text) ?? Decimal.zero,
      category: _category,
      accountId: _selectedAccountId,
      type: _type,
      createRule: _createRule,
    );

    result.fold(
      (failure) => ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure.message))),
      (_) {
        widget.onComplete();
        dashboard.refresh(); // Refresh dashboard to update counts
        if (mounted) Navigator.pop(context);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoadingAccounts) {
      _loadAccounts();
    }

    return SafeArea(
      bottom: true,
      child: Container(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.dividerColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Neural Forensic',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Text(
                          'AI-Assisted Transaction Labeling',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    if (!_isAIParsing)
                      ElevatedButton.icon(
                        onPressed: _runAIForensic,
                        icon: const Icon(Icons.auto_awesome, size: 14),
                        label: const Text(
                          'AI Analysis',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary.withValues(
                            alpha: 0.1,
                          ),
                          foregroundColor: AppTheme.primary,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(100),
                          ),
                        ),
                      )
                    else
                      const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),

                const SizedBox(height: 24),

                // Raw Message Container
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: theme.dividerColor.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.terminal,
                            size: 14,
                            color: AppTheme.primary.withValues(alpha: 0.8),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'RAW EVIDENCE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.primary.withValues(alpha: 0.8),
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.message.content,
                        style: TextStyle(
                          fontFamily: 'Courier',
                          fontSize: 13,
                          height: 1.5,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.8,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // Amount and Type
                if (_errorMessage != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.red.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: Colors.red,
                            size: 16,
                          ),
                          onPressed: () => setState(() => _errorMessage = null),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'AMOUNT',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.6),
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _amountController,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: _isAmountAI
                                  ? AppTheme.primary
                                  : theme.colorScheme.onSurface,
                            ),
                            decoration: InputDecoration(
                              hintText: '0.00',
                              prefixIcon: const Padding(
                                padding: EdgeInsets.only(right: 8, left: 12),
                                child: Icon(Icons.currency_rupee, size: 18),
                              ),
                              prefixIconConstraints: const BoxConstraints(
                                minWidth: 0,
                                minHeight: 0,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              filled: true,
                              fillColor: _isAmountAI
                                  ? AppTheme.primary.withValues(alpha: 0.05)
                                  : theme.colorScheme.surface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(
                                  color: theme.dividerColor,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(
                                  color: theme.dividerColor.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                              ),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TYPE',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.6),
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            height: 48, // Compact
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: theme.dividerColor.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                _buildTypeOption(
                                  'DEBIT',
                                  AppTheme.danger,
                                  theme,
                                ),
                                _buildTypeOption(
                                  'CREDIT',
                                  AppTheme.success,
                                  theme,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Description
                Text(
                  'MERCHANT / RECIPIENT',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.6,
                    ),
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _descController,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _isDescAI
                        ? AppTheme.primary
                        : theme.colorScheme.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Enter name...',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    filled: true,
                    fillColor: _isDescAI
                        ? AppTheme.primary.withValues(alpha: 0.05)
                        : theme.colorScheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: theme.dividerColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: theme.dividerColor.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Account and Date
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ACCOUNT',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.6),
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SearchablePicker(
                            title: 'Select Account',
                            items: _accounts,
                            placeholder: 'Select Account',
                            selectedValue: _selectedAccountId != null
                                ? {
                                    'id': _selectedAccountId,
                                    'name': _selectedAccountName,
                                  }
                                : null,
                            labelMapper: (a) => a['name'] as String,
                            onSelected: (a) {
                              setState(() {
                                _selectedAccountId = a['id'] as String;
                                _selectedAccountName = a['name'] as String;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'DATE',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.6),
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: _selectDate,
                            child: Container(
                              height: 48, // Compact
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: theme.dividerColor.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.calendar_today,
                                    size: 14,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    DateFormat('dd MMM').format(_date),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Category
                Text(
                  'CATEGORY',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.6,
                    ),
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                CategoryPickerField(
                  selectedCategory: _category,
                  isHighlighted: _isCategoryAI,
                  onCategorySelected: (val) {
                    setState(() {
                      _category = val;
                      _isCategoryAI = false;
                    });
                  },
                ),

                const SizedBox(height: 32),

                // Rule Generation Toggle
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.bolt, color: AppTheme.primary, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Auto-Learn Feature',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              'Generate pattern for future matches',
                              style: TextStyle(
                                fontSize: 10,
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _createRule,
                        onChanged: (v) => setState(() => _createRule = v),
                        activeThumbColor: AppTheme.primary,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Submit
                ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 56),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'FINALIZE FORENSIC',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          letterSpacing: 0.5,
                        ),
                      ),
                      SizedBox(width: 10),
                      Icon(Icons.check_circle_outline, size: 18),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTypeOption(String label, Color color, ThemeData theme) {
    bool isSelected = _type == label;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _type = label),
        child: Container(
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isSelected ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: isSelected
                  ? Colors.white
                  : theme.colorScheme.onSurface.withValues(alpha: 0.2),
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}
