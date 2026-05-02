import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:mobile_app/core/theme/app_theme.dart';
import 'package:mobile_app/modules/home/services/goals_service.dart';
import 'package:mobile_app/modules/home/services/dashboard_service.dart';
import 'package:mobile_app/core/widgets/app_shell.dart';
import 'package:mobile_app/modules/home/screens/expense_group_details_screen.dart';

class ExpenseGroupsScreen extends StatefulWidget {
  const ExpenseGroupsScreen({super.key});

  @override
  State<ExpenseGroupsScreen> createState() => _ExpenseGroupsScreenState();
}

class _ExpenseGroupsScreenState extends State<ExpenseGroupsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GoalsService>().fetchExpenseGroups();
    });
  }

  @override
  Widget build(BuildContext context) {
    final goalsService = context.watch<GoalsService>();

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: const DrawerMenuButton(),
        title: const Text('Expense Groups'),
      ),
      body: RefreshIndicator(
        onRefresh: () => goalsService.fetchExpenseGroups(),
        child: goalsService.isLoading && goalsService.expenseGroups.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : goalsService.error != null && goalsService.expenseGroups.isEmpty
            ? ListView(
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                  Center(
                    child: Text(
                      goalsService.error!,
                      style: const TextStyle(color: AppTheme.danger),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton.icon(
                      onPressed: () => goalsService.fetchExpenseGroups(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ),
                ],
              )
            : _buildExpenseGroupsList(goalsService, goalsService.expenseGroups),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddGroupDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddGroupDialog(BuildContext context) {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final budgetController = TextEditingController();
    final iconController = TextEditingController(text: '📁');

    DateTime startDate = DateTime.now();
    DateTime endDate = DateTime.now().add(const Duration(days: 30));

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New Expense Group'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: iconController,
                  decoration: const InputDecoration(
                    labelText: 'Icon (Emoji)',
                    hintText: 'e.g. 🎒, 🏠',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Group Name',
                    hintText: 'e.g. Goa Trip 2024',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
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
                          if (picked != null) {
                            setDialogState(() => startDate = picked);
                          }
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Start Date',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
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
                          if (picked != null) {
                            setDialogState(() => endDate = picked);
                          }
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'End Date',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
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
                  decoration: const InputDecoration(
                    labelText: 'Budget (Optional)',
                    prefixText: '₹ ',
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final service = context.read<GoalsService>();
                final success = await service.createExpenseGroup({
                  'name': nameController.text,
                  'description': descriptionController.text,
                  'icon': iconController.text,
                  'budget': double.tryParse(budgetController.text) ?? 0.0,
                  'start_date': startDate.toIso8601String(),
                  'end_date': endDate.toIso8601String(),
                  'is_active': true,
                });
                if (!context.mounted) return;
                if (success) Navigator.pop(context);
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpenseGroupsList(GoalsService service, List<dynamic> groups) {
    if (groups.isEmpty) {
      return ListView(
        // Needs to be scrollable for RefreshIndicator to work
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.3),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.group_work_outlined,
                  size: 80,
                  color: AppTheme.primary.withValues(alpha: 0.2),
                ),
                const SizedBox(height: 24),
                Text(
                  'No expense groups found',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Create a group for an event or shared trip',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final dashboard = context.read<DashboardService>();
    final currency = dashboard.currencySymbol;
    final maskingFactor = dashboard.maskingFactor;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        final budget = (group['budget'] ?? 0.0).toDouble();
        final spent = (group['total_spend'] ?? 0.0).toDouble();
        final progress = budget > 0 ? (spent / budget).clamp(0.0, 1.0) : 0.0;
        final isOverBudget = spent > budget && budget > 0;
        final isActive = group['is_active'] ?? true;

        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey.withValues(alpha: 0.1)),
          ),
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ExpenseGroupDetailsScreen(group: group),
                ),
              );
            },
            onLongPress: () => _showDeleteConfirm(context, group, service),
            borderRadius: BorderRadius.circular(16),
            child: Opacity(
              opacity: isActive ? 1.0 : 0.6,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child:
                              group['icon'] != null && group['icon'].isNotEmpty
                              ? Text(
                                  group['icon'],
                                  style: const TextStyle(fontSize: 24),
                                )
                              : const Icon(
                                  Icons.group_work,
                                  color: AppTheme.primary,
                                  size: 24,
                                ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      group['name'] ?? 'Unnamed Group',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                      ),
                                    ),
                                  ),
                                  if (!isActive)
                                    _buildStatusBadge('Inactive', Colors.grey)
                                  else if (budget > 0)
                                    _buildStatusBadge(
                                      isOverBudget ? 'Over Budget' : 'On Track',
                                      isOverBudget
                                          ? AppTheme.danger
                                          : AppTheme.success,
                                    ),
                                ],
                              ),
                              if (group['description'] != null &&
                                  group['description'].isNotEmpty)
                                Text(
                                  group['description'],
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 13,
                                  ),
                                ),
                              if (group['start_date'] != null ||
                                  group['end_date'] != null)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 4,
                                    bottom: 4,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.calendar_today_outlined,
                                        size: 11,
                                        color: Colors.grey[400],
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${group['start_date'] != null ? DateFormat('MMM d, yyyy').format(DateTime.parse(group['start_date'])) : "..."}'
                                        ' - '
                                        '${group['end_date'] != null ? DateFormat('MMM d, yyyy').format(DateTime.parse(group['end_date'])) : "..."}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[600],
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: Colors.grey),
                      ],
                    ),
                    if (budget > 0) ...[
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Spending Progress',
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            '$currency${(spent / maskingFactor).toStringAsFixed(0)} / $currency${(budget / maskingFactor).toStringAsFixed(0)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isOverBudget
                                  ? AppTheme.danger
                                  : AppTheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 8,
                          backgroundColor:
                              (isOverBudget
                                      ? AppTheme.danger
                                      : AppTheme.primary)
                                  .withValues(alpha: 0.1),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isOverBudget ? AppTheme.danger : AppTheme.primary,
                          ),
                        ),
                      ),
                    ] else ...[
                      Row(
                        children: [
                          const Icon(
                            Icons.wallet,
                            size: 14,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Total Spent: $currency${(spent / maskingFactor).toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showDeleteConfirm(
    BuildContext context,
    dynamic group,
    GoalsService service,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Group?'),
        content: Text('Are you sure you want to delete "${group['name']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final success = await service.deleteExpenseGroup(
                group['id'].toString(),
              );
              if (!context.mounted) return;
              if (success) Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 9,
          color: color,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
