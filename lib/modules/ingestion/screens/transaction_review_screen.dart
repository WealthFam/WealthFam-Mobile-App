import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_app/core/config/app_config.dart';
import 'package:mobile_app/core/theme/app_theme.dart';
import 'package:mobile_app/core/widgets/category_picker.dart';
import 'package:mobile_app/modules/auth/services/auth_service.dart';
import 'package:mobile_app/modules/home/models/dashboard_data.dart';
import 'package:mobile_app/modules/home/services/dashboard_service.dart';
import 'package:mobile_app/modules/home/services/categories_service.dart';
import 'package:decimal/decimal.dart';

class TransactionReviewScreen extends StatefulWidget {
  const TransactionReviewScreen({super.key});

  @override
  State<TransactionReviewScreen> createState() => _TransactionReviewScreenState();
}

class _TransactionReviewScreenState extends State<TransactionReviewScreen> {
  List<RecentTransaction> _triageItems = [];
  bool _isLoading = true;
  String? _error;
  
  final Map<String, String> _selectedCategories = {};
  final Map<String, bool> _createRuleFlags = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final config = context.read<AppConfig>();
      final auth = context.read<AuthService>();
      final url = Uri.parse('${config.backendUrl}/api/v1/ingestion/triage');
      final response = await http.get(url, headers: {'Authorization': 'Bearer ${auth.accessToken}'});
      
      if (response.statusCode == 200) {
        final List raw = jsonDecode(utf8.decode(response.bodyBytes))['data'] ?? [];
        final items = raw.map((i) => RecentTransaction.fromJson(i)).toList();
        
        setState(() {
          _triageItems = items;
          for (var item in _triageItems) {
            _selectedCategories[item.id] = item.category;
            _createRuleFlags[item.id] = true;
          }
          _isLoading = false;
        });
      } else {
        throw Exception('Failed to load reviews');
      }
    } catch (e) {
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _processTriage(String id, bool approve) async {
    final config = context.read<AppConfig>();
    final auth = context.read<AuthService>();

    try {
      if (approve) {
         final url = Uri.parse('${config.backendUrl}/api/v1/ingestion/triage/$id/approve');
         final response = await http.post(
           url,
           headers: {'Authorization': 'Bearer ${auth.accessToken}', 'Content-Type': 'application/json'},
           body: jsonEncode({
             'category': _selectedCategories[id] ?? 'Uncategorized',
             'create_rule': _createRuleFlags[id] ?? false,
           }),
         );
         if (response.statusCode != 200) throw Exception('Approval failed');
      } else {
         final url = Uri.parse('${config.backendUrl}/api/v1/ingestion/triage/$id');
         final response = await http.delete(url, headers: {'Authorization': 'Bearer ${auth.accessToken}'});
         if (response.statusCode != 200) throw Exception('Discard failed');
      }
      
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(approve ? 'Approved' : 'Discarded')));
      _loadData();
      context.read<DashboardService>().refresh();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Action failed: $e'), backgroundColor: AppTheme.danger));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = context.watch<DashboardService>().data?.pendingTriageCount ?? 0;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Review Hub ($count)', style: const TextStyle(fontWeight: FontWeight.w900)),
        elevation: 0,
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : _error != null
               ? Center(child: Text(_error!, style: const TextStyle(color: AppTheme.danger)))
               : _triageItems.isEmpty
                   ? _buildEmptyState()
                   : RefreshIndicator(
                       onRefresh: _loadData,
                       child: ListView.separated(
                         padding: const EdgeInsets.all(16),
                         itemCount: _triageItems.length,
                         separatorBuilder: (_, __) => const SizedBox(height: 16),
                         itemBuilder: (context, index) => _buildTriageCard(_triageItems[index]),
                       ),
                     ),
    );
  }

  Widget _buildEmptyState() {
     return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline, size: 80, color: AppTheme.success.withOpacity(0.2)),
          const SizedBox(height: 20),
          const Text('All Clear!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const Text('No pending reviews for now.', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildTriageCard(RecentTransaction item) {
    final theme = Theme.of(context);
    final dashboard = context.read<DashboardService>();
    final category = _selectedCategories[item.id] ?? 'Uncategorized';
    final createRule = _createRuleFlags[item.id] ?? true;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 6)),
          BoxShadow(color: (item.amount < Decimal.zero ? AppTheme.danger : AppTheme.success).withOpacity(0.02), blurRadius: 10, spreadRadius: -5),
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
                    Text(item.description, 
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: -0.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: theme.scaffoldBackgroundColor, borderRadius: BorderRadius.circular(10)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.account_balance_wallet_outlined, size: 12, color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5)),
                          const SizedBox(width: 8),
                          Flexible(child: Text('${item.source ?? "Unknown Source"} • ${item.accountName ?? "Unknown"} • ${item.formattedDate}', 
                            style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7), fontSize: 11, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${dashboard.currencySymbol}${(item.amount.abs().toDouble() / dashboard.maskingFactor).toStringAsFixed(0)}', 
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: item.amount < Decimal.zero ? AppTheme.danger : AppTheme.success, letterSpacing: -0.5)),
                  Text(item.amount < Decimal.zero ? 'DEBIT' : 'CREDIT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5, color: (item.amount < Decimal.zero ? AppTheme.danger : AppTheme.success).withOpacity(0.5))),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          CategoryPickerField(
            selectedCategory: category,
            onCategorySelected: (cat) => setState(() => _selectedCategories[item.id] = cat),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Transform.scale(scale: 0.8, child: Switch(
                value: createRule, 
                onChanged: (v) => setState(() => _createRuleFlags[item.id] = v), 
                activeColor: AppTheme.primary,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              )),
              Text('Sync as Rule', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: theme.colorScheme.onSurfaceVariant.withOpacity(0.8))),
              const Spacer(),
              TextButton(
                onPressed: () => _processTriage(item.id, false), 
                style: TextButton.styleFrom(foregroundColor: AppTheme.danger, padding: const EdgeInsets.symmetric(horizontal: 16)),
                child: const Text('Discard', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => _processTriage(item.id, true), 
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.success, 
                  foregroundColor: Colors.white, 
                  elevation: 0,
                  minimumSize: const Size(80, 40),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                ),
                child: const Text('Approve', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
