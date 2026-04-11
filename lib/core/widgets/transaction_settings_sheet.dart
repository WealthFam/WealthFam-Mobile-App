import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:mobile_app/core/config/app_config.dart';
import 'package:mobile_app/core/theme/app_theme.dart';
import 'package:mobile_app/modules/auth/services/auth_service.dart';
import 'package:mobile_app/modules/home/models/dashboard_data.dart';
import 'package:mobile_app/modules/home/services/dashboard_service.dart';
import 'package:mobile_app/modules/home/services/categories_service.dart';
import 'package:mobile_app/modules/home/models/transaction_category.dart';
import 'package:mobile_app/core/widgets/category_picker.dart';
import 'package:mobile_app/modules/vault/services/vault_service.dart';
import 'package:mobile_app/modules/vault/screens/vault_screen.dart';
import 'package:file_picker/file_picker.dart';

class TransactionSettingsSheet extends StatefulWidget {
  final RecentTransaction transaction;
  final bool isTriage; 
  final Function(bool isTransfer, bool excludeFromReports)? onSaved;

  const TransactionSettingsSheet({
    super.key,
    required this.transaction,
    this.isTriage = false,
    this.onSaved,
  });

  static Future<dynamic> show(
    BuildContext context, 
    RecentTransaction transaction, {
    bool isTriage = false,
    Function(bool isTransfer, bool excludeFromReports)? onSaved,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TransactionSettingsSheet(
        transaction: transaction,
        isTriage: isTriage,
        onSaved: onSaved,
      ),
    );
  }

  @override
  State<TransactionSettingsSheet> createState() => _TransactionSettingsSheetState();
}

class _TransactionSettingsSheetState extends State<TransactionSettingsSheet> {
  late bool _isTransfer;
  late bool _excludeFromReports;
  late String _selectedCategory;
  bool _createRule = false;
  bool _isSaving = false;
  
  // Transfer Linking
  String? _targetAccountId;
  String? _linkedTransactionId;
  List<dynamic> _accounts = [];
  List<dynamic> _matches = [];
  bool _isLoadingMatches = false;
  late Future<List<VaultDocument>> _evidenceFuture;

  @override
  void initState() {
    super.initState();
    _isTransfer = widget.transaction.isTransfer;
    _excludeFromReports = widget.transaction.excludeFromReports;
    _selectedCategory = widget.transaction.category;
    _evidenceFuture = context.read<VaultService>().getLinkedDocuments(widget.transaction.id);
    
    Future.delayed(Duration.zero, () {
      context.read<CategoriesService>().fetchCategories();
      _fetchAccounts();
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
        setState(() => _accounts = jsonDecode(response.body));
      }
    } catch (e) {
      debugPrint("Error fetching accounts: $e");
    }
  }

  Future<void> _fetchMatches() async {
    if (_targetAccountId == null) return;
    setState(() => _isLoadingMatches = true);
    
    final config = context.read<AppConfig>();
    final auth = context.read<AuthService>();
    
    try {
      final dateStr = widget.transaction.date.toUtc().toIso8601String();
      final url = Uri.parse('${config.backendUrl}/api/v1/mobile/ingestion/matches').replace(
        queryParameters: {
          'amount': widget.transaction.amount.toString(),
          'date': dateStr,
          'account_id': widget.transaction.accountId ?? '',
          'target_account_id': _targetAccountId,
        },
      );

      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer ${auth.accessToken}'},
      );

      if (response.statusCode == 200) {
        setState(() => _matches = jsonDecode(response.body));
      }
    } catch (e) {
      debugPrint("Error fetching matches: $e");
    } finally {
      if (mounted) setState(() => _isLoadingMatches = false);
    }
  }

  Future<void> _handleFileUpload() async {
    final vault = context.read<VaultService>();
    
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );
    
    if (result != null && result.files.single.path != null) {
      final file = result.files.single;
      
      // Step 1: Fetch existing folders to let user pick
      if (!mounted) return;
      final folders = await vault.getFolders();
      
      final controller = TextEditingController(text: file.name);
      String selectedType = "INVOICE";
      String? selectedFolderId; // Null means ROOT or we find/create Bills by default
      
      try {
        selectedFolderId = folders.firstWhere((f) => f.filename == "Bills").id;
      } catch (_) {
        // Bills folder doesn't exist yet, it'll be created if they stick with default
      }

      final uploadData = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('Evidence Details', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.5)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(labelText: 'FileName', hintText: 'filename.pdf'),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedType,
                    decoration: const InputDecoration(labelText: 'Document Category'),
                    items: ['INVOICE', 'BILL', 'POLICY', 'TAX', 'IDENTITY', 'OTHER']
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (val) => setDialogState(() => selectedType = val!),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String?>(
                    value: selectedFolderId,
                    decoration: const InputDecoration(labelText: 'Target Folder'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Root Vault (or create Bills)')),
                      ...folders.where((f) => f.isFolder).map((f) => DropdownMenuItem(value: f.id, child: Text(f.filename))),
                    ],
                    onChanged: (val) => setDialogState(() => selectedFolderId = val),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, {
                    'name': controller.text, 
                    'type': selectedType,
                    'folderId': selectedFolderId,
                  }),
                  child: const Text('Upload'),
                ),
              ],
            );
          },
        ),
      );
      
      if (uploadData == null) return;
      final fileName = uploadData['name'] ?? file.name;
      final fileType = uploadData['type'] ?? "INVOICE";

      // Step 2: Proceed with upload
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
      
      try {
        // 1. Get or create target folder
        String? targetFolderId = uploadData['folderId'];
        if (targetFolderId == null) {
          targetFolderId = await vault.getOrCreateFolderByName("Bills");
        }
        
        // 2. Upload and link
        final uploadResult = await vault.uploadDocument(
          filePath: file.path!,
          fileName: fileName,
          fileType: fileType,
          transactionId: widget.transaction.id,
          parentId: targetFolderId,
        );
        
        if (mounted) Navigator.pop(context); // Close loading
        
        uploadResult.fold(
          (failure) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Upload failed: ${failure.message}'), backgroundColor: AppTheme.danger),
            );
          },
          (_) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Evidence uploaded and linked!'), backgroundColor: AppTheme.success),
            );
            setState(() {
              _evidenceFuture = vault.getLinkedDocuments(widget.transaction.id);
            });
          },
        );
      } catch (e) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text('Upload failed: $e'), backgroundColor: AppTheme.danger),
          );
        }
      }
    }
  }

  Future<void> _save() async {
    if (widget.isTriage) {
      if (widget.onSaved != null) {
        widget.onSaved!(_isTransfer, _excludeFromReports);
      }
      Navigator.pop(context);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final config = context.read<AppConfig>();
      final auth = context.read<AuthService>();
      final catService = context.read<CategoriesService>();

      // 1. Update Category if changed or rule requested
      if (_selectedCategory != widget.transaction.category || _createRule) {
        await catService.updateTransactionCategory(
          widget.transaction.id, 
          _selectedCategory,
          createRule: _createRule,
          keywords: [widget.transaction.description],
        );
      }

      // 2. Update Flags (Transfer/Exclude)
      final url = Uri.parse('${config.backendUrl}/api/v1/finance/transactions/${widget.transaction.id}');
      final response = await http.put(
        url,
        headers: {
          'Authorization': 'Bearer ${auth.accessToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'is_transfer': _isTransfer,
          'exclude_from_reports': _excludeFromReports,
          if (_isTransfer && _targetAccountId != null) 'to_account_id': _targetAccountId,
          if (_isTransfer && _linkedTransactionId != null) 'linked_transaction_id': _linkedTransactionId,
        }),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Transaction updated')),
          );
          context.read<DashboardService>().refresh();
          Navigator.pop(context, true);
        }
      } else {
        throw Exception('Failed to update transaction flags');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categoriesService = context.watch<CategoriesService>();
    
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 30,
            offset: const Offset(0, -10),
          )
        ],
      ),
      padding: EdgeInsets.only(
        top: 20,
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 40,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Edit Transaction',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5),
          ),
          const SizedBox(height: 4),
          Text(
            widget.transaction.description,
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7), fontSize: 14),
          ),
          const SizedBox(height: 32),
          
          // Category Selection (Hierarchical UI)
          const Text('Category', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 0.5)),
          const SizedBox(height: 12),
          CategoryPickerField(
            selectedCategory: _selectedCategory,
            onCategorySelected: (cat) => setState(() => _selectedCategory = cat),
          ),
          
          // Smart Rule Toggle
          if (!widget.isTriage) ...[
            const SizedBox(height: 16),
            InkWell(
              onTap: () => setState(() => _createRule = !_createRule),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    SizedBox(
                      height: 24,
                      width: 24,
                      child: Checkbox(
                        value: _createRule,
                        onChanged: (v) => setState(() => _createRule = v!),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Apply to similar transactions (Create Rule)',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          
          const SizedBox(height: 32),
          const Text('Advanced Settings', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 0.5)),
          const SizedBox(height: 12),
          
          _buildToggle(
            title: 'Internal Transfer',
            subtitle: 'Money moved between your own accounts',
            icon: Icons.swap_horiz_rounded,
            value: _isTransfer,
            onChanged: (v) {
              setState(() {
                _isTransfer = v;
                if (v) {
                  _excludeFromReports = true;
                  if (_accounts.isNotEmpty && _targetAccountId == null) {
                    // Pre-select first different account if possible
                    _targetAccountId = _accounts.firstWhere((a) => a['id'] != widget.transaction.accountId, orElse: () => null)?['id'];
                    _fetchMatches();
                  }
                }
              });
            },
          ),
          
          if (_isTransfer) ...[
             const SizedBox(height: 16),
             Container(
               padding: const EdgeInsets.all(16),
               decoration: BoxDecoration(
                 color: theme.primaryColor.withValues(alpha: 0.05),
                 borderRadius: BorderRadius.circular(20),
                 border: Border.all(color: theme.primaryColor.withValues(alpha: 0.1)),
               ),
               child: Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                    const Text('Destination Account', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _targetAccountId,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: _accounts.map((a) => DropdownMenuItem(value: a['id'] as String, child: Text(a['name'] as String))).toList(),
                      onChanged: (v) {
                        setState(() => _targetAccountId = v);
                        _fetchMatches();
                      },
                    ),
                    if (_isLoadingMatches)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: LinearProgressIndicator(),
                      )
                    else if (_matches.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Icon(Icons.auto_awesome, size: 14, color: Colors.blue),
                          const SizedBox(width: 8),
                          Text('SUGGESTED MATCHES (${_matches.length})', 
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: Colors.blue, letterSpacing: 0.5)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ..._matches.map((m) {
                        final isSelected = _linkedTransactionId == m['id'];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            onTap: () => setState(() => _linkedTransactionId = isSelected ? null : m['id']),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: isSelected ? Colors.blue : Colors.grey.withValues(alpha: 0.1)),
                                color: isSelected ? Colors.blue.withValues(alpha: 0.05) : theme.scaffoldBackgroundColor.withValues(alpha: 0.3),
                              ),
                              child: Row(
                                children: [
                                  Icon(isSelected ? Icons.check_circle : Icons.circle_outlined, 
                                    size: 18, color: isSelected ? Colors.blue : Colors.grey.withValues(alpha: 0.5)),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(m['description'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                        Text('${m['account_name']} • ${m['amount']}', style: TextStyle(fontSize: 11, color: Colors.grey.withValues(alpha: 0.7))),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 8),
                      const Text(
                        'Select a matching transaction to link them, or save to create a new one.',
                        style: TextStyle(fontSize: 10, color: Colors.grey, fontStyle: FontStyle.italic),
                      ),
                    ] else if (_targetAccountId != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, size: 16, color: Colors.orange),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'No matching transactions found in destination account. Saving will create a new linked transaction.',
                                style: TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                 ],
               ),
             ),
          ],
          const SizedBox(height: 12),
          _buildToggle(
            title: 'Exclude from Reports',
            subtitle: 'Don\'t count this in spending analytics',
            icon: Icons.visibility_off_outlined,
            value: _excludeFromReports,
            onChanged: (v) => setState(() => _excludeFromReports = v),
          ),
          
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Evidence', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 0.5)),
              TextButton.icon(
                onPressed: _handleFileUpload,
                icon: const Icon(Icons.add_a_photo_outlined, size: 16),
                label: const Text('Add Receipt', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<VaultDocument>>(
            future: _evidenceFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ));
              }
              final docs = snapshot.data ?? [];
              if (docs.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.receipt_long_outlined, size: 32, color: theme.disabledColor.withValues(alpha: 0.3)),
                      const SizedBox(height: 8),
                      Text('No evidence linked yet', style: TextStyle(color: theme.disabledColor, fontSize: 12)),
                    ],
                  ),
                );
              }
              
              return Column(
                children: docs.map((doc) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
                  ),
                  child: ListTile(
                    dense: true,
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: theme.primaryColor.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: doc.thumbnailPath != null 
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              context.read<VaultService>().getThumbnailUrl(doc.id),
                              headers: context.read<VaultService>().authHeaders,
                              fit: BoxFit.cover,
                            ),
                          )
                        : const Icon(Icons.description_outlined, size: 20, color: AppTheme.primary),
                    ),
                    title: Text(doc.filename, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    subtitle: Text(doc.formattedSize, style: const TextStyle(fontSize: 11)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.folder_open_outlined, size: 18),
                          tooltip: 'Show in Vault',
                          onPressed: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => VaultScreen(initialFolderId: doc.parentId ?? 'ROOT'),
                              ),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.open_in_new, size: 18),
                          onPressed: () async {
                            final vault = context.read<VaultService>();
                            final result = await vault.saveDocument(doc);
                            result.fold(
                              (failure) => ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(failure.message), backgroundColor: AppTheme.danger),
                              ),
                              (path) => OpenFilex.open(path),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                )).toList(),
              );
            },
          ),
          
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                elevation: 0,
              ),
              child: _isSaving
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                : const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggle({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: value ? AppTheme.primary.withValues(alpha: 0.3) : theme.dividerColor.withValues(alpha: 0.05)),
          borderRadius: BorderRadius.circular(20),
          color: value ? AppTheme.primary.withValues(alpha: 0.05) : theme.scaffoldBackgroundColor.withValues(alpha: 0.5),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: value ? AppTheme.primary.withValues(alpha: 0.1) : theme.dividerColor.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: value ? AppTheme.primary : Colors.grey, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6))),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: AppTheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}
