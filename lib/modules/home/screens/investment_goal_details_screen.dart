import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:mobile_app/core/config/app_config.dart';
import 'package:mobile_app/core/theme/app_theme.dart';
import 'package:mobile_app/modules/auth/services/auth_service.dart';
import 'package:mobile_app/modules/home/services/dashboard_service.dart';
import 'package:mobile_app/modules/home/services/goals_service.dart';

class InvestmentGoalDetailsScreen extends StatefulWidget {
  final dynamic goal;
  const InvestmentGoalDetailsScreen({super.key, required this.goal});

  @override
  State<InvestmentGoalDetailsScreen> createState() => _InvestmentGoalDetailsScreenState();
}

class _InvestmentGoalDetailsScreenState extends State<InvestmentGoalDetailsScreen> {
  late dynamic _goal;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _goal = widget.goal;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      refreshData();
    });
  }

  Future<void> refreshData() async {
    setState(() => _isLoading = true);
    final config = context.read<AppConfig>();
    final auth = context.read<AuthService>();

    try {
      final response = await http.get(
        Uri.parse('${config.backendUrl}/api/v1/mobile/investment-goals/${_goal['id']}'),
        headers: {'Authorization': 'Bearer ${auth.accessToken}'},
      );

      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _goal = jsonDecode(response.body);
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching goal details: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dashboard = context.read<DashboardService>();
    final currency = dashboard.currencySymbol;
    final target = double.tryParse(_goal['target_amount']?.toString() ?? '0') ?? 0.0;
    final current = double.tryParse(_goal['current_amount']?.toString() ?? '0') ?? 0.0;
    final progress = target > 0 ? (current / target).clamp(0.0, 1.0) : 0.0;
    final remaining = double.tryParse(_goal['remaining_amount']?.toString() ?? '0') ?? 0.0;

    final holdings = _goal['holdings'] as List? ?? [];
    final assets = _goal['assets'] as List? ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text(_goal['name'] ?? 'Goal Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _showEditGoalDialog(context),
            tooltip: 'Edit Goal',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppTheme.danger),
            onPressed: () => _showDeleteConfirm(context),
            tooltip: 'Delete Goal',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refreshData,
        child: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSummaryCard(current, target, progress, remaining, currency),
                const SizedBox(height: 24),
                if (holdings.isNotEmpty) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSectionHeader('Linked Mutual Funds', AppTheme.primary),
                      TextButton.icon(
                        onPressed: _showLinkHoldingDialog,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Link New'),
                      ),
                    ],
                  ),
                  ...holdings.map((h) => _buildHoldingTile(h, currency)),
                  const SizedBox(height: 16),
                ],
                if (assets.isNotEmpty) ...[
                  _buildSectionHeader('Linked Bank Accounts & Assets', AppTheme.success),
                  ...assets.map((a) => _buildAssetTile(a, currency)),
                  const SizedBox(height: 16),
                ],
                if (holdings.isEmpty && assets.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Column(
                        children: [
                          Icon(Icons.link_off, size: 48, color: theme.disabledColor),
                          const SizedBox(height: 8),
                          Text(
                            'No investments linked to this goal yet.',
                            style: TextStyle(color: theme.disabledColor),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _showLinkHoldingDialog,
                            icon: const Icon(Icons.add),
                            label: const Text('Link Investments'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
      ),
    );
  }

  Widget _buildSummaryCard(double current, double target, double progress, double remaining, String currency) {
    final theme = Theme.of(context);
    final maskingFactor = context.read<DashboardService>().maskingFactor;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primary, AppTheme.primary.withBlue(200)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Overall Progress',
                style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${(progress * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withOpacity(0.1),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              minHeight: 10,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              _buildMetric('Current', '$currency${(current / maskingFactor).toStringAsFixed(0)}'),
              const Spacer(),
              _buildMetric('Target', '$currency${(target / maskingFactor).toStringAsFixed(0)}'),
              const Spacer(),
              _buildMetric('Remaining', '$currency${(remaining / maskingFactor).toStringAsFixed(0)}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildSectionHeader(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(width: 4, height: 16, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildHoldingTile(dynamic h, String currency) {
    final val = double.tryParse(h['current_value']?.toString() ?? '0') ?? 0.0;
    final maskingFactor = context.read<DashboardService>().maskingFactor;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onLongPress: () => _showUnlinkConfirm(h['scheme_name'], h['id'].toString()),
        leading: CircleAvatar(
          backgroundColor: AppTheme.primary.withOpacity(0.1),
          child: const Icon(Icons.show_chart, color: AppTheme.primary, size: 20),
        ),
        title: Text(h['scheme_name'] ?? 'Scheme', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Text('Folio: ${h['folio_number'] ?? 'N/A'}', style: const TextStyle(fontSize: 12)),
        trailing: Text(
          '$currency${(val / maskingFactor).toStringAsFixed(0)}',
          style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary),
        ),
      ),
    );
  }

  Widget _buildAssetTile(dynamic a, String currency) {
    final val = double.tryParse(a['current_value']?.toString() ?? '0') ?? 0.0;
    final maskingFactor = context.read<DashboardService>().maskingFactor;
    
    IconData icon = Icons.account_balance_wallet_outlined;
    if (a['type'] == 'BANK_ACCOUNT') icon = Icons.account_balance_outlined;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppTheme.success.withOpacity(0.1),
          child: Icon(icon, color: AppTheme.success, size: 20),
        ),
        title: Text(a['display_name'] ?? a['name'] ?? 'Asset', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Text(a['type']?.toString().replaceAll('_', ' ') ?? 'Manual', style: const TextStyle(fontSize: 12)),
        trailing: Text(
          '$currency${(val / maskingFactor).toStringAsFixed(0)}',
          style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.success),
        ),
      ),
    );
  }

  void _showDeleteConfirm(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Goal?'),
        content: Text('Are you sure you want to delete "${_goal['name']}"? Linked holdings will be unlinked but not deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final success = await context.read<GoalsService>().deleteGoal(_goal['id'].toString());
              if (success && mounted) {
                Navigator.pop(context); // Close dialog
                Navigator.pop(context); // Go back from details
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showEditGoalDialog(BuildContext context) {
    final nameController = TextEditingController(text: _goal['name']);
    final targetController = TextEditingController(text: _goal['target_amount'].toString());
    final descriptionController = TextEditingController(text: _goal['description']);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Goal'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Goal Name')),
            TextField(
              controller: targetController,
              decoration: const InputDecoration(labelText: 'Target Amount'),
              keyboardType: TextInputType.number,
            ),
            TextField(controller: descriptionController, decoration: const InputDecoration(labelText: 'Description')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final success = await context.read<GoalsService>().updateGoal(_goal['id'].toString(), {
                'name': nameController.text,
                'target_amount': double.tryParse(targetController.text) ?? 0,
                'description': descriptionController.text,
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
    );
  }

  void _showUnlinkConfirm(String name, String holdingId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unlink Holding?'),
        content: Text('Remove "$name" from this goal?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final config = context.read<AppConfig>();
              final auth = context.read<AuthService>();
              final response = await http.post(
                Uri.parse('${config.backendUrl}/api/v1/mobile/investment-goals/unlink'),
                headers: {
                  'Authorization': 'Bearer ${auth.accessToken}',
                  'Content-Type': 'application/json',
                },
                body: jsonEncode({'holding_id': holdingId}),
              );
              if (response.statusCode == 200 && mounted) {
                Navigator.pop(context);
                refreshData();
              }
            },
            child: const Text('Unlink', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _showLinkHoldingDialog() async {
    final config = context.read<AppConfig>();
    final auth = context.read<AuthService>();

    // Fetch common portfolio to pick from
    final response = await http.get(
      Uri.parse('${config.backendUrl}/api/v1/mobile/funds'),
      headers: {'Authorization': 'Bearer ${auth.accessToken}'},
    );

    if (response.statusCode != 200) return;
    
    final data = jsonDecode(response.body);
    final List<dynamic> portfolio = data['holdings'] ?? [];
    
    // Filter out already linked to this goal
    final linkedIds = (_goal['holdings'] as List).map((h) => h['id'].toString()).toSet();
    final available = portfolio.where((h) => !linkedIds.contains(h['scheme_code'].toString())).toList();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Link Mutual Fund'),
        content: SizedBox(
          width: double.maxFinite,
          child: available.isEmpty 
            ? const Text('All your funds are already linked or no funds found.')
            : ListView.builder(
                shrinkWrap: true,
                itemCount: available.length,
                itemBuilder: (context, index) {
                  final h = available[index];
                  final double val = double.tryParse(h['current_value']?.toString() ?? '0') ?? 0.0;
                  final maskingFactor = context.read<DashboardService>().maskingFactor;
                  final currency = context.read<DashboardService>().currencySymbol;

                  return ListTile(
                    title: Text(h['scheme_name'] ?? 'Unknown Fund'),
                    subtitle: Text('Current Value: $currency${(val / maskingFactor).toStringAsFixed(0)}'),
                    onTap: () async {
                      final linkRes = await http.post(
                        Uri.parse('${config.backendUrl}/api/v1/mobile/investment-goals/${_goal['id']}/link'),
                        headers: {
                          'Authorization': 'Bearer ${auth.accessToken}',
                          'Content-Type': 'application/json',
                        },
                        body: jsonEncode({'holding_id': h['scheme_code'].toString()}),
                      );
                      if (linkRes.statusCode == 200 && mounted) {
                        Navigator.pop(context);
                        refreshData();
                      }
                    },
                  );
                },
              ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }
}
