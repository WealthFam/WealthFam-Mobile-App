import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_app/core/config/app_config.dart';
import 'package:mobile_app/core/theme/app_theme.dart';
import 'package:mobile_app/core/widgets/category_picker.dart';
import 'package:mobile_app/modules/auth/services/auth_service.dart';
import 'package:mobile_app/modules/home/models/dashboard_data.dart';
import 'package:mobile_app/modules/home/services/dashboard_service.dart';
import 'package:provider/provider.dart';

class TransactionReviewScreen extends StatefulWidget {
  const TransactionReviewScreen({super.key});

  @override
  State<TransactionReviewScreen> createState() =>
      _TransactionReviewScreenState();
}

class _TransactionReviewScreenState extends State<TransactionReviewScreen> {
  List<RecentTransaction> _triageItems = [];
  bool _isLoading = true;
  String? _error;

  final Map<String, String> _selectedCategories = {};
  final Map<String, bool> _createRuleFlags = {};
  final Map<String, bool> _transferFlags = {};
  final Map<String, bool> _excludeFlags = {};
  final Map<String, String?> _toAccountIds = {};
  final Map<String, String?> _linkedTransactionIds = {};
  final Map<String, List<dynamic>> _potentialMatches = {};

  @override
  void initState() {
    super.initState();
    _loadData();
    _fetchAccounts();
  }

  List<dynamic> _accounts = [];
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
          _accounts = jsonDecode(response.body) as List<dynamic>;
        });
      }
    } catch (e) {
      debugPrint('Error fetching accounts: $e');
    }
  }

  Future<void> _fetchMatches(String pendingId) async {
    final config = context.read<AppConfig>();
    final auth = context.read<AuthService>();
    try {
      final response = await http.get(
        Uri.parse(
          '${config.backendUrl}/api/v1/mobile/ingestion/triage/$pendingId/matches',
        ),
        headers: {'Authorization': 'Bearer ${auth.accessToken}'},
      );
      if (response.statusCode == 200) {
        setState(() {
          _potentialMatches[pendingId] = jsonDecode(response.body) as List<dynamic>;
        });
      }
    } catch (e) {
      debugPrint('Error fetching matches: $e');
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final config = context.read<AppConfig>();
      final auth = context.read<AuthService>();
      final url = Uri.parse('${config.backendUrl}/api/v1/ingestion/triage');
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer ${auth.accessToken}'},
      );

      if (response.statusCode == 200) {
        final raw =
            (jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>)['data'] as List<dynamic>? ?? [];
        final items = raw.map((i) => RecentTransaction.fromJson(i as Map<String, dynamic>)).toList();

        setState(() {
          _triageItems = items;
          for (var item in _triageItems) {
            _selectedCategories[item.id] = item.category;
            _createRuleFlags[item.id] = true;
            _transferFlags[item.id] = item.isTransfer;
            _excludeFlags[item.id] = item.excludeFromReports;
            _toAccountIds[item.id] = null;
            _linkedTransactionIds[item.id] = null;
          }
          _isLoading = false;
        });
      } else {
        throw Exception('Failed to load reviews');
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<bool> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    Color? confirmColor,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            content: Text(message, style: const TextStyle(fontSize: 14)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: confirmColor ?? AppTheme.danger,
                  foregroundColor: Colors.white,
                  elevation: 0,
                ),
                child: Text(
                  confirmLabel,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _processTriage(String id, bool approve) async {
    final config = context.read<AppConfig>();
    final auth = context.read<AuthService>();

    final messenger = ScaffoldMessenger.of(context);
    final dashboardService = context.read<DashboardService>();
    try {
      if (approve) {
        final url = Uri.parse(
          '${config.backendUrl}/api/v1/ingestion/triage/$id/approve',
        );
        final response = await http.post(
          url,
          headers: {
            'Authorization': 'Bearer ${auth.accessToken}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'category': _selectedCategories[id] ?? 'Uncategorized',
            'create_rule': _createRuleFlags[id] ?? false,
            'is_transfer': _transferFlags[id] ?? false,
            'exclude_from_reports': _excludeFlags[id] ?? false,
            'to_account_id': _toAccountIds[id],
            'linked_transaction_id': _linkedTransactionIds[id],
          }),
        );
        if (response.statusCode != 200) throw Exception('Approval failed');
      } else {
        // ADD CONFIRMATION FOR DISCARD
        final confirm = await _showConfirmDialog(
          title: 'Discard Transaction?',
          message:
              'This transaction will be permanently removed from triage. You can always manually add it later if needed.',
          confirmLabel: 'Discard',
        );
        if (!confirm) return;

        final url = Uri.parse(
          '${config.backendUrl}/api/v1/ingestion/triage/$id',
        );
        final response = await http.delete(
          url,
          headers: {'Authorization': 'Bearer ${auth.accessToken}'},
        );
        if (response.statusCode != 200) throw Exception('Discard failed');
      }

      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(approve ? 'Approved' : 'Discarded')),
      );
      _loadData();
      dashboardService.refresh();
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Action failed: $e'),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count =
        context.watch<DashboardService>().data?.pendingTriageCount ?? 0;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Review Hub ($count)',
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Text(
                _error!,
                style: const TextStyle(color: AppTheme.danger),
              ),
            )
          : _triageItems.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _triageItems.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 16),
                itemBuilder: (context, index) =>
                    _buildTriageCard(_triageItems[index]),
              ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 80,
            color: AppTheme.success.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 20),
          const Text(
            'All Clear!',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const Text(
            'No pending reviews for now.',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildTriageCard(RecentTransaction item) {
    final theme = Theme.of(context);
    final dashboard = context.read<DashboardService>();
    final category = _selectedCategories[item.id] ?? 'Uncategorized';
    final createRule = _createRuleFlags[item.id] ?? true;
    final isTransfer = _transferFlags[item.id] ?? false;
    final isExcluded = _excludeFlags[item.id] ?? false;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.description,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        letterSpacing: -0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item.accountName ?? 'Unknown'} • ${item.formattedDate}',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.6,
                        ),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${dashboard.currencySymbol}${(item.amount.abs().toDouble() / dashboard.maskingFactor).toStringAsFixed(0)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                      color: item.amount < Decimal.zero
                          ? AppTheme.danger
                          : AppTheme.success,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Text(
                    item.amount < Decimal.zero ? 'DEBIT' : 'CREDIT',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                      color:
                          (item.amount < Decimal.zero
                                  ? AppTheme.danger
                                  : AppTheme.success)
                              .withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          CategoryPickerField(
            selectedCategory: category,
            onCategorySelected: (cat) =>
                setState(() => _selectedCategories[item.id] = cat),
          ),

          if (isTransfer) ...[
            const SizedBox(height: 16),
            _buildTransferSection(item),
          ],

          const SizedBox(height: 16),
          _buildActionRow(item, theme, isTransfer, isExcluded, createRule),
        ],
      ),
    );
  }

  Widget _buildTransferSection(RecentTransaction item) {
    final theme = Theme.of(context);
    final toAccountId = _toAccountIds[item.id];
    final matches = _potentialMatches[item.id];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DESTINATION ACCOUNT',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 10,
              letterSpacing: 1,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: toAccountId,
            isExpanded: true,
            decoration: InputDecoration(
              filled: true,
              fillColor: theme.colorScheme.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
            hint: const Text('Select Account', style: TextStyle(fontSize: 13)),
            items: _accounts.where((a) => (a as Map<String, dynamic>)['id'] != item.accountId).map((aRaw) {
              final a = aRaw as Map<String, dynamic>;
              return DropdownMenuItem(
                value: a['id'] as String,
                child: Text(a['name'] as String, style: const TextStyle(fontSize: 13)),
              );
            }).toList(),
            onChanged: (v) {
              setState(() {
                _toAccountIds[item.id] = v;
                _linkedTransactionIds[item.id] = null;
              });
              _fetchMatches(item.id);
            },
          ),
          if (toAccountId != null) ...[
            const SizedBox(height: 12),
            const Text(
              'LINK TO EXISTING (OPTIONAL)',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 10,
                letterSpacing: 1,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            if (matches == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (matches.isEmpty)
              const Text(
                'No matching transactions found.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              )
            else
              _buildMatchPicker(item.id, matches),
          ],
        ],
      ),
    );
  }

  Widget _buildMatchPicker(String pendingId, List<dynamic> matches) {
    final theme = Theme.of(context);
    return Column(
      children: matches.map((mRaw) {
        final m = mRaw as Map<String, dynamic>;
        final isSelected = _linkedTransactionIds[pendingId] == m['id'];
        return InkWell(
          onTap: () => setState(
            () =>
                _linkedTransactionIds[pendingId] = isSelected ? null : m['id'] as String?
          ),
          child: Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.primary.withValues(alpha: 0.1)
                  : theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected
                    ? AppTheme.primary
                    : theme.dividerColor.withValues(alpha: 0.05),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m['description'] as String,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                      ),
                      Text(
                        '${m['account_name']} • ${m['date'].toString().split('T')[0]}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${(m['amount'] as num) > 0 ? "+" : ""}${m['amount']}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: (m['amount'] as num) > 0 ? AppTheme.success : AppTheme.danger,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  isSelected ? Icons.link : Icons.link_off,
                  size: 16,
                  color: isSelected ? AppTheme.primary : Colors.grey,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildActionRow(
    RecentTransaction item,
    ThemeData theme,
    bool isTransfer,
    bool isExcluded,
    bool createRule,
  ) {
    return Row(
      children: [
        // Quick Toggles
        _buildActionIcon(
          icon: isTransfer
              ? Icons.swap_horiz_rounded
              : Icons.swap_horiz_outlined,
          color: isTransfer
              ? AppTheme.primary
              : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          onTap: () {
            setState(() {
              _transferFlags[item.id] = !isTransfer;
              if (!isTransfer) _excludeFlags[item.id] = true;
            });
            if (!isTransfer) _fetchMatches(item.id);
          },
          tooltip: 'Mark as Transfer',
        ),
        const SizedBox(width: 8),
        _buildActionIcon(
          icon: isExcluded
              ? Icons.visibility_off_rounded
              : Icons.visibility_off_outlined,
          color: isExcluded
              ? AppTheme.warning
              : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          onTap: () => setState(() => _excludeFlags[item.id] = !isExcluded),
          tooltip: 'Exclude from Reports',
        ),
        const SizedBox(width: 16),

        // Discard
        IconButton(
          onPressed: () => _processTriage(item.id, false),
          icon: const Icon(
            Icons.close_rounded,
            color: AppTheme.danger,
            size: 22,
          ),
          tooltip: 'Discard',
        ),

        const Spacer(),

        // Approve Button
        ElevatedButton(
          onPressed: () => _processTriage(item.id, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.success,
            foregroundColor: Colors.white,
            elevation: 0,
            minimumSize: const Size(100, 44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: const Text(
            'Approve',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }

  Widget _buildActionIcon({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }
}
