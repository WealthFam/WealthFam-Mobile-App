import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_app/core/theme/app_theme.dart';
import 'package:mobile_app/core/widgets/transaction_settings_sheet.dart';
import 'package:mobile_app/modules/home/models/dashboard_data.dart';
import 'package:mobile_app/modules/home/services/dashboard_service.dart';
import 'package:provider/provider.dart';

class TransactionDetailScreen extends StatelessWidget {

  const TransactionDetailScreen({required this.transaction, super.key});
  final RecentTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final dashboard = context.watch<DashboardService>();
    final theme = Theme.of(context);
    final currencyFormat = NumberFormat.currency(
      symbol: dashboard.currencySymbol,
      decimalDigits: 2,
    );

    final amount = transaction.amount.toDouble() / dashboard.maskingFactor;
    final formattedAmount = currencyFormat.format(amount);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppTheme.primary.withValues(alpha: 0.8),
                      AppTheme.primary,
                    ],
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 40),
                      Text(
                        formattedAmount,
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          transaction.category,
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () {
                  TransactionSettingsSheet.show(context, transaction);
                },
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoCard(theme, transaction),
                  const SizedBox(height: 24),
                  _buildTimelineSection(theme, transaction),
                  const SizedBox(height: 24),
                  _buildEvidenceSection(theme, transaction),
                  const SizedBox(height: 40),
                  _buildActionButtons(context, transaction),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(ThemeData theme, RecentTransaction tx) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildInfoRow(Icons.description_outlined, 'Description', tx.description),
            const Divider(height: 24),
            _buildInfoRow(Icons.calendar_today_outlined, 'Date & Time', tx.formattedDate),
            const Divider(height: 24),
            _buildInfoRow(Icons.account_balance_wallet_outlined, 'Account', tx.accountName ?? 'Manual Entry'),
            if (tx.accountOwnerName != null) ...[
              const Divider(height: 24),
              _buildInfoRow(Icons.person_outline, 'Owner', tx.accountOwnerName!),
            ],
            const Divider(height: 24),
            _buildInfoRow(
              Icons.tag_outlined,
              'Source',
              tx.source?.toUpperCase() ?? 'DIRECT',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTimelineSection(ThemeData theme, RecentTransaction tx) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Transaction Timeline',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        _buildTimelineItem(
          'Detected',
          'Transaction recognized via ${tx.source ?? 'manual entry'}',
          tx.formattedDate,
          true,
          false,
        ),
        _buildTimelineItem(
          'Categorized',
          'Auto-assigned to ${tx.category}',
          '',
          false,
          false,
        ),
        _buildTimelineItem(
          'Synced',
          'Successfully archived to cloud ledger',
          '',
          false,
          true,
        ),
      ],
    );
  }

  Widget _buildTimelineItem(
    String title,
    String subtitle,
    String time,
    bool isFirst,
    bool isLast,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                color: AppTheme.primary,
                shape: BoxShape.circle,
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 40,
                color: AppTheme.primary.withValues(alpha: 0.2),
              ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (time.isNotEmpty)
                    Text(time, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEvidenceSection(ThemeData theme, RecentTransaction tx) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Evidence & Receipts',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            TextButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.add_a_photo_outlined, size: 18),
              label: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (!tx.hasDocuments)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!, style: BorderStyle.none),
            ),
            child: const Column(
              children: [
                Icon(Icons.receipt_long_outlined, color: Colors.grey, size: 40),
                SizedBox(height: 8),
                Text(
                  'No evidence linked yet',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          )
        else
          const Center(child: Text('Linked Documents UI Here')),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context, RecentTransaction tx) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.share_outlined),
            label: const Text('Share'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.archive_outlined),
            label: const Text('Archive'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }
}
