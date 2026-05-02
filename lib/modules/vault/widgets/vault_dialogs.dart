import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_app/core/errors/either.dart';
import 'package:mobile_app/core/errors/failures.dart';
import 'package:mobile_app/core/theme/app_theme.dart';
import 'package:mobile_app/modules/home/models/transaction_category.dart';
import 'package:mobile_app/modules/home/services/categories_service.dart';
import 'package:mobile_app/modules/home/services/dashboard_service.dart';
import 'package:mobile_app/modules/vault/services/vault_service.dart';
import 'package:provider/provider.dart';

class TransactionPickerSheet extends StatefulWidget {
  const TransactionPickerSheet({
    required this.docId,
    required this.service,
    super.key,
  });

  final String docId;
  final VaultService service;

  @override
  State<TransactionPickerSheet> createState() => _TransactionPickerSheetState();
}

class _TransactionPickerSheetState extends State<TransactionPickerSheet> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Text(
                    'Link Transaction',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search merchant or amount...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.grey.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (val) {
                  setState(() => query = val);
                },
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: FutureBuilder<Either<Failure, List<dynamic>>>(
                key: ValueKey(query),
                future: widget.service.searchTransactions(query: query),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return snapshot.data?.fold(
                        (failure) => Center(child: Text(failure.message)),
                        (txns) {
                          if (txns.isEmpty) {
                            return const Center(
                              child: Text('No transactions found'),
                            );
                          }
                          return ListView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            itemCount: txns.length,
                            itemBuilder: (context, index) {
                              final Map<String, dynamic> txn = txns[index] as Map<String, dynamic>;
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppTheme.primary.withValues(
                                    alpha: 0.1,
                                  ),
                                  child: Text(
                                    txn['category'] != null &&
                                            txn['category']
                                                .toString()
                                                .isNotEmpty
                                        ? txn['category']
                                            .toString()[0]
                                            .toUpperCase()
                                        : 'T',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primary,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  (txn['description'] as String?) ??
                                      'No Description',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                subtitle: Text(
                                  (txn['date'] as String?) ?? '',
                                  style: const TextStyle(fontSize: 10),
                                ),
                                trailing: Text(
                                  '₹${txn['amount']}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.primary,
                                  ),
                                ),
                                onTap: () => Navigator.pop(context, txn['id'] as String?),
                              );
                            },
                          );
                        },
                      ) ??
                      const Center(child: Text('Error loading transactions'));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LinkedTransactionInfo extends StatelessWidget {
  const LinkedTransactionInfo({required this.tx, super.key});

  final LinkedTransaction tx;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dashboard = context.read<DashboardService>();
    final amount = tx.amount.toDouble();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Icon(Icons.link, size: 12, color: theme.primaryColor),
                const SizedBox(width: 6),
                Text(
                  'LINKED TRANSACTION',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: theme.primaryColor,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
            ),
            leading: Consumer<CategoriesService>(
              builder: (context, catService, _) {
                final catNameRaw = tx.category ?? 'Other';
                final catName = catNameRaw.contains(' › ')
                    ? catNameRaw.split(' › ').last
                    : catNameRaw;
                TransactionCategory? matched;

                for (var parent in catService.categories) {
                  if (parent.name.toLowerCase() == catName.toLowerCase()) {
                    matched = parent;
                    break;
                  }
                  for (var sub in parent.subcategories) {
                    if (sub.name.toLowerCase() == catName.toLowerCase()) {
                      matched = sub;
                      break;
                    }
                  }
                  if (matched != null) break;
                }

                return Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    matched?.icon ??
                        (catName.isNotEmpty ? catName[0].toUpperCase() : '?'),
                    style: TextStyle(
                      fontSize: 18,
                      color: theme.primaryColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              },
            ),
            title: Text(
              tx.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            subtitle: Text(
              '${DateFormat('d MMM, h:mm a').format(tx.date)} • ${tx.accountName ?? 'Account'}',
              style: TextStyle(
                fontSize: 10,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.6,
                ),
                fontWeight: FontWeight.w500,
              ),
            ),
            trailing: Text(
              NumberFormat.simpleCurrency(
                name: 'INR',
                decimalDigits: 0,
              ).format(amount / dashboard.maskingFactor),
              style: TextStyle(
                color: amount < 0 ? AppTheme.danger : AppTheme.success,
                fontWeight: FontWeight.w900,
                fontSize: 14,
                letterSpacing: -0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class VaultDocumentDetailsSheet extends StatelessWidget {
  const VaultDocumentDetailsSheet({
    required this.doc,
    required this.service,
    required this.scrollController,
    super.key,
  });

  final VaultDocument doc;
  final VaultService service;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: AppTheme.primary),
                const SizedBox(width: 12),
                const Text(
                  'Document Details',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                _buildDetailRow('Filename', doc.filename),
                _buildDetailRow('Type', doc.fileType),
                if (!doc.isFolder) _buildDetailRow('Size', doc.formattedSize),
                if (!doc.isFolder)
                  _buildDetailRow('MIME Type', doc.mimeType ?? 'Unknown'),
                _buildDetailRow(
                  'Created',
                  DateFormat('dd MMM yyyy, h:mm a').format(doc.createdAt),
                ),
                if (doc.description != null && doc.description!.isNotEmpty)
                  _buildDetailRow('Description', doc.description!),
                if (doc.transactionId != null) ...[
                  const Divider(height: 32),
                  const Text(
                    'LINKED TRANSACTION',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: Colors.grey,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (doc.linkedTransaction != null)
                    LinkedTransactionInfo(tx: doc.linkedTransaction!)
                  else
                    const Text(
                      'Transaction ID: Linked (Refresh to see details)',
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
