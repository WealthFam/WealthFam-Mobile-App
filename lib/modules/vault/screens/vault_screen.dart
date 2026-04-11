import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_app/core/theme/app_theme.dart';
import 'package:mobile_app/modules/vault/services/vault_service.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:mobile_app/core/widgets/app_shell.dart';
import 'package:mobile_app/core/errors/either.dart';
import 'package:mobile_app/core/errors/failures.dart';
import 'package:decimal/decimal.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  bool _isGridView = true;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VaultService>().fetchDocuments();
    });
  }

  @override
  Widget build(BuildContext context) {
    final vaultService = context.watch<VaultService>();
    final theme = Theme.of(context);
    final filteredDocs = vaultService.documents;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: vaultService.canGoBack || vaultService.isSelectionMode
          ? IconButton(
              icon: Icon(vaultService.isSelectionMode ? Icons.close : Icons.arrow_back),
              onPressed: () {
                if (vaultService.isSelectionMode) {
                  vaultService.clearSelection();
                } else {
                  vaultService.goBack();
                }
              },
            )
          : const DrawerMenuButton(),
        title: vaultService.isSelectionMode 
          ? Text('${vaultService.selectedIds.length} Selected', style: const TextStyle(fontWeight: FontWeight.bold))
          : _isSearching 
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: const InputDecoration(
                  hintText: 'Search documents...',
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                ),
                onChanged: (value) => vaultService.fetchDocuments(search: value),
              )
            : const Text('Documents Vault'),
        actions: [
          if (vaultService.isSelectionMode) ...[
            IconButton(
              icon: const Icon(Icons.drive_file_move_outlined),
              onPressed: () => _showMovePicker(context, vaultService.selectedIds.toList()),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppTheme.danger),
              onPressed: () => _handleBulkDelete(context),
            ),
          ]
          else ...[
            IconButton(
              icon: Icon(_isSearching ? Icons.close : Icons.search),
              onPressed: () {
                setState(() {
                  _isSearching = !_isSearching;
                  if (!_isSearching) {
                    _searchController.clear();
                    vaultService.fetchDocuments();
                  }
                });
              },
            ),
            IconButton(
              icon: Icon(_isGridView ? Icons.list : Icons.grid_view),
              onPressed: () => setState(() => _isGridView = !_isGridView),
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildVaultSummary(vaultService),
            _buildBreadcrumbs(vaultService),
            _buildFilterBar(vaultService),
            Expanded(
              child: RefreshIndicator(
              onRefresh: () => vaultService.fetchDocuments(),
              child: vaultService.isLoading && vaultService.documents.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : vaultService.error != null
                      ? _buildErrorState(vaultService.error!)
                      : filteredDocs.isEmpty
                          ? _buildEmptyState()
                          : _isGridView 
                              ? _buildGridView(vaultService, filteredDocs)
                              : _buildListView(vaultService, filteredDocs),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddMenu(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Upload File'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickAndUpload(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder),
              title: const Text('New Folder'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showCreateFolderDialog(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreateFolderDialog(BuildContext context) async {
    final controller = TextEditingController();
    final service = context.read<VaultService>();
    final messenger = ScaffoldMessenger.of(context);
    
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Folder Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                final result = await service.createFolder(controller.text);
                result.fold(
                  (failure) {
                    messenger.showSnackBar(
                      SnackBar(content: Text(failure.message), backgroundColor: AppTheme.danger),
                    );
                  },
                  (_) {
                    if (mounted) Navigator.pop(context);
                  },
                );
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumbs(VaultService service) {
    if (service.breadcrumbs.length <= 1) return const SizedBox.shrink();
    
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.1))),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: service.breadcrumbs.length,
        separatorBuilder: (_, __) => const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
        itemBuilder: (context, index) {
          final crumb = service.breadcrumbs[index];
          final isLast = index == service.breadcrumbs.length - 1;
          
          return TextButton(
            onPressed: isLast ? null : () => service.navigateToBreadcrumb(index),
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              foregroundColor: isLast ? AppTheme.primary : Colors.grey,
            ),
            child: Text(
              crumb['name']!,
              style: TextStyle(
                fontWeight: isLast ? FontWeight.w900 : FontWeight.w600,
                fontSize: 12,
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _handleBulkDelete(BuildContext context) async {
    final service = context.read<VaultService>();
    final count = service.selectedIds.length;
    final messenger = ScaffoldMessenger.of(context);
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $count items?'),
        content: const Text('This action cannot be undone. All selected files and subfolders will be permanently removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: const Text('Delete', style: TextStyle(color: AppTheme.danger, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final result = await service.bulkDelete();
      result.fold(
        (failure) {
          messenger.showSnackBar(
            SnackBar(content: Text(failure.message), backgroundColor: AppTheme.danger),
          );
        },
        (_) {
          messenger.showSnackBar(
            SnackBar(content: Text('Deleted $count items')),
          );
        },
      );
    }
  }

  Widget _buildFilterBar(VaultService vaultService) {
    final types = ['ALL', 'INVOICE', 'POLICY', 'TAX', 'IDENTITY', 'OTHER'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: types.map((type) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilterChip(
            selected: vaultService.fileType == type,
            label: Text(type, style: const TextStyle(fontSize: 10)),
            onSelected: (selected) {
              vaultService.setFileType(type);
            },
          ),
        )).toList(),
      ),
    );
  }

  Future<void> _pickAndUpload(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final service = context.read<VaultService>();
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (!mounted) return;

      if (result != null && result.files.single.path != null) {
        final file = result.files.single;
        
        final metadata = await _showUploadMetadataDialog(context, file.name);
        if (metadata == null) return;

        final uploadResult = await service.uploadDocument(
          filePath: file.path!,
          fileName: metadata['name']!,
          fileType: metadata['type']!,
        );

        if (!mounted) return;

        uploadResult.fold(
          (failure) {
             messenger.showSnackBar(
              SnackBar(content: Text('Upload error: ${failure.message}'), backgroundColor: AppTheme.danger),
            );
          },
          (_) {
            messenger.showSnackBar(
              SnackBar(content: Text('Uploaded ${file.name}')),
            );
          },
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Upload error: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  Widget _buildErrorState(String error) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.6,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppTheme.danger),
            const SizedBox(height: 16),
            Text(error, style: const TextStyle(color: AppTheme.danger), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => context.read<VaultService>().fetchDocuments(),
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.6,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 80, color: AppTheme.primary.withOpacity(0.2)),
            const SizedBox(height: 16),
            const Text(
              'No documents here yet',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 8),
            const Text('Upload your first document or create a folder'),
          ],
        ),
      ),
    );
  }

  Widget _buildGridView(VaultService service, List<VaultDocument> documents) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.85,
      ),
      itemCount: documents.length,
      itemBuilder: (context, index) {
        final doc = documents[index];
        return _buildDocCard(doc, service);
      },
    );
  }

  Widget _buildListView(VaultService service, List<VaultDocument> documents) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: documents.length,
      itemBuilder: (context, index) {
        final doc = documents[index];
        final isSelected = service.selectedIds.contains(doc.id);
        
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          elevation: isSelected ? 4 : 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isSelected ? AppTheme.primary : Colors.black.withOpacity(0.05),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: ListTile(
            leading: _buildFileIcon(doc, service, size: 40),
            title: Text(doc.filename, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${doc.isFolder ? 'Folder' : doc.fileType} • ${doc.formattedSize}'),
            selected: isSelected,
            trailing: service.isSelectionMode
                ? Checkbox(
                    value: isSelected,
                    onChanged: (_) => service.toggleSelection(doc.id),
                    activeColor: AppTheme.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  )
                : IconButton(
                    icon: const Icon(Icons.more_vert),
                    onPressed: () => _showActionSheet(doc, service),
                  ),
            onTap: () {
              if (service.isSelectionMode) {
                service.toggleSelection(doc.id);
              } else {
                _handleTap(doc, service);
              }
            },
            onLongPress: () => service.toggleSelection(doc.id),
          ),
        );
      },
    );
  }

  Widget _buildDocCard(VaultDocument doc, VaultService service) {
    final theme = Theme.of(context);
    final isSelected = service.selectedIds.contains(doc.id);
    
    return Card(
      elevation: isSelected ? 12 : 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? AppTheme.primary : theme.dividerColor.withOpacity(0.1),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: () {
          if (service.isSelectionMode) {
            service.toggleSelection(doc.id);
          } else {
            _handleTap(doc, service);
          }
        },
        onLongPress: () => service.toggleSelection(doc.id),
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primary.withOpacity(0.05) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildFileIcon(doc, service, size: 64),
                    if (service.isSelectionMode)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)],
                          ),
                          child: Checkbox(
                            value: isSelected,
                            onChanged: (_) => service.toggleSelection(doc.id),
                            activeColor: AppTheme.primary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          ),
                        ),
                      ),
                    if (!service.isSelectionMode)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: IconButton(
                          icon: const Icon(Icons.more_vert, size: 20, color: Colors.black45),
                          onPressed: () => _showActionSheet(doc, service),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(12.0),
                color: theme.colorScheme.surface.withOpacity(isSelected ? 0.0 : 0.8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: -0.3),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          doc.isFolder ? 'Folder' : doc.fileType,
                          style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          DateFormat('dd MMM').format(doc.createdAt),
                          style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5), fontSize: 9),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFileIcon(VaultDocument doc, VaultService service, {required double size}) {
    Widget content;
    
    if (doc.isFolder) {
      content = Icon(Icons.folder, size: size, color: Colors.amber);
    } else if (doc.thumbnailPath != null) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          service.getThumbnailUrl(doc.id),
          headers: service.authHeaders,
          fit: BoxFit.cover,
          errorBuilder: (context, _, __) => _buildPlaceholder(doc, size),
        ),
      );
    } else {
      content = _buildPlaceholder(doc, size);
    }

    return SizedBox(
      width: size,
      height: size,
      child: content,
    );
  }

  Widget _buildPlaceholder(VaultDocument doc, double size) {
    IconData icon;
    Color color;
    
    switch (doc.fileType.toUpperCase()) {
      case 'INVOICE':
        icon = Icons.receipt_long;
        color = Colors.blue;
        break;
      case 'POLICY':
        icon = Icons.verified_user;
        color = Colors.green;
        break;
      case 'IDENTITY':
        icon = Icons.badge;
        color = Colors.purple;
        break;
      case 'TAX':
        icon = Icons.account_balance;
        color = Colors.orange;
        break;
      default:
        icon = Icons.insert_drive_file;
        color = Colors.grey;
    }

    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: size * 0.6, color: color.withOpacity(0.8)),
    );
  }

  void _handleTap(VaultDocument doc, VaultService service) {
    if (doc.isFolder) {
      service.navigateToFolder(doc.id, doc.filename);
    } else {
      _showActionSheet(doc, service);
    }
  }
  void _showActionSheet(VaultDocument doc, VaultService service) {
    final messenger = ScaffoldMessenger.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (context, scrollController) => SafeArea(
          child: ListView(
            controller: scrollController,
            shrinkWrap: true,
            children: [
              ListTile(
                leading: _buildFileIcon(doc, service, size: 32),
                title: Text(doc.filename, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                subtitle: Text(doc.isFolder ? 'Folder' : '${doc.fileType} • ${doc.formattedSize}'),
              ),
              if (doc.linkedTransaction != null) ...[
                const Divider(indent: 16, endIndent: 16),
                _buildTransactionInfo(doc.linkedTransaction!),
              ],
              const Divider(),
              if (!doc.isFolder) ...[
                ListTile(
                  leading: const Icon(Icons.remove_red_eye_outlined),
                  title: const Text('View Document'),
                  onTap: () {
                    Navigator.pop(context);
                    _openDocument(doc, service);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('Download'),
                  onTap: () async {
                    Navigator.pop(context);
                    final result = await service.saveDocument(doc);
                    result.fold(
                      (failure) {
                        messenger.showSnackBar(
                          SnackBar(content: Text(failure.message), backgroundColor: AppTheme.danger),
                        );
                      },
                      (path) {
                        messenger.showSnackBar(
                          SnackBar(content: Text('Saved to: $path')),
                        );
                      },
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.share_outlined),
                  title: const Text('Send with...'),
                  onTap: () => Navigator.pop(context),
                ),
              ],
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Details'),
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Rename'),
                onTap: () {
                  Navigator.pop(context);
                  _showRenameDialog(context, doc);
                },
              ),
              ListTile(
                leading: Icon(doc.linkedTransaction != null ? Icons.link_off : Icons.link),
                title: Text(doc.linkedTransaction != null ? 'Unlink Transaction' : 'Link to Transaction'),
                onTap: () {
                  Navigator.pop(context);
                  if (doc.linkedTransaction != null) {
                    _handleUnlink(doc.id, service);
                  } else {
                    _showTransactionPicker(context, doc.id, service);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.drive_file_move_outlined),
                title: const Text('Move to Folder'),
                onTap: () {
                  Navigator.pop(context);
                  _showMovePicker(context, [doc.id]);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppTheme.danger),
                title: const Text('Delete', style: TextStyle(color: AppTheme.danger)),
                onTap: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Delete?'),
                      content: Text('Are you sure you want to delete ${doc.filename}?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true), 
                          child: const Text('Delete', style: TextStyle(color: AppTheme.danger)),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    final result = await service.deleteDocument(doc.id);
                    result.fold(
                      (failure) {
                        messenger.showSnackBar(
                          SnackBar(content: Text(failure.message), backgroundColor: AppTheme.danger),
                        );
                      },
                      (_) {
                        // All good
                      },
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVaultSummary(VaultService service) {
    if (_isSearching) return const SizedBox.shrink();
    
    final totalSize = service.documents.fold<double>(0, (sum, doc) => sum + doc.fileSize);
    final fileCount = service.documents.where((d) => !d.isFolder).length;
    final folderCount = service.documents.where((d) => d.isFolder).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primary.withOpacity(0.1), AppTheme.primary.withOpacity(0.0)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Row(
        children: [
          _buildSummaryItem(Icons.insert_drive_file_outlined, '$fileCount Files'),
          const SizedBox(width: 16),
          _buildSummaryItem(Icons.folder_outlined, '$folderCount Folders'),
          const Spacer(),
          _buildSummaryItem(Icons.storage, _formatSize(totalSize), color: AppTheme.primary),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(IconData icon, String value, {Color? color}) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color ?? Colors.grey),
        const SizedBox(width: 4),
        Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  String _formatSize(double bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    double size = bytes;
    int suffixIndex = 0;
    while (size >= 1024 && suffixIndex < suffixes.length - 1) {
      size /= 1024;
      suffixIndex++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[suffixIndex]}';
  }

  void _showMovePicker(BuildContext context, List<String> docIds) {
    final service = context.read<VaultService>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Move to Folder', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
            ),
            Expanded(
              child: ListView(
                children: [
                  ListTile(
                    leading: const Icon(Icons.home_outlined),
                    title: const Text('Root Vault', style: TextStyle(fontWeight: FontWeight.bold)),
                    onTap: () async {
                      final result = await service.moveDocuments(docIds, 'ROOT');
                      if (mounted) Navigator.pop(context);
                      _handleActionResult(result, 'Moved successfully');
                    },
                  ),
                  const Divider(),
                  ...service.documents.where((d) => d.isFolder && !docIds.contains(d.id)).map((folder) => ListTile(
                    leading: const Icon(Icons.folder_outlined, color: Colors.amber),
                    title: Text(folder.filename, style: const TextStyle(fontWeight: FontWeight.bold)),
                    onTap: () async {
                      final result = await service.moveDocuments(docIds, folder.id);
                      if (mounted) Navigator.pop(context);
                      _handleActionResult(result, 'Moved to ${folder.filename}');
                    },
                  )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTransactionPicker(BuildContext context, String docId, VaultService service) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Transaction selection coming soon...')),
    );
  }

  Future<void> _handleUnlink(String docId, VaultService service) async {
    final result = await service.linkTransaction(docId, null);
    _handleActionResult(result, 'Unlinked successfully');
  }

  void _handleActionResult(Either<Failure, Unit> result, String successMsg) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    result.fold(
      (failure) => messenger.showSnackBar(
        SnackBar(content: Text(failure.message), backgroundColor: AppTheme.danger),
      ),
      (_) => messenger.showSnackBar(
        SnackBar(content: Text(successMsg)),
      ),
    );
  }

  Widget _buildTransactionInfo(LinkedTransaction tx) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.primary.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.primary.withOpacity(0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.link, size: 14, color: AppTheme.primary),
                const SizedBox(width: 8),
                Text('LINKED EVIDENCE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppTheme.primary, letterSpacing: 1)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tx.description, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(DateFormat('dd MMM yyyy').format(tx.date), style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant.withOpacity(0.6))),
                    ],
                  ),
                ),
                Text(
                  '₹${tx.amount.toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: -0.5),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<Map<String, String>?> _showUploadMetadataDialog(BuildContext context, String initialName) async {
    String type = 'OTHER';
    final controller = TextEditingController(text: initialName);
    
    return showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Upload Document'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'FileName'),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: type,
                decoration: const InputDecoration(labelText: 'Document Type'),
                items: ['OTHER', 'INVOICE', 'POLICY', 'TAX', 'IDENTITY']
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (val) => setDialogState(() => type = val!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, {'name': controller.text, 'type': type}),
              child: const Text('Proceed'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRenameDialog(BuildContext context, VaultDocument doc) async {
    final controller = TextEditingController(text: doc.filename);
    String type = doc.fileType.toUpperCase();
    final service = context.read<VaultService>();
    final messenger = ScaffoldMessenger.of(context);

    return showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Details'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'FileName'),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: type,
                decoration: const InputDecoration(labelText: 'Document Type'),
                items: ['OTHER', 'INVOICE', 'POLICY', 'TAX', 'IDENTITY']
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (val) => setDialogState(() => type = val!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (controller.text.isNotEmpty) {
                  final result = await service.updateDocumentMetadata(
                    doc.id, 
                    newName: controller.text != doc.filename ? controller.text : null,
                    newType: type != doc.fileType.toUpperCase() ? type : null,
                  );
                  result.fold(
                    (failure) {
                      messenger.showSnackBar(
                        SnackBar(content: Text(failure.message), backgroundColor: AppTheme.danger),
                      );
                    },
                    (_) {
                      if (mounted) Navigator.pop(context);
                    },
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDocument(VaultDocument doc, VaultService service) async {
    try {
      final result = await service.saveDocument(doc);
      result.fold(
        (failure) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(failure.message), backgroundColor: AppTheme.danger),
            );
          }
        },
        (path) async {
          await OpenFilex.open(path);
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open file: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }
}
