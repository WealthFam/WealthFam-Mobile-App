import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';

import 'package:mobile_app/core/theme/app_theme.dart';
import 'package:mobile_app/modules/vault/services/vault_service.dart';
import 'package:mobile_app/core/widgets/app_shell.dart';
import 'package:mobile_app/core/errors/either.dart';
import 'package:mobile_app/core/errors/failures.dart';
import 'package:mobile_app/modules/home/services/categories_service.dart';
import 'package:mobile_app/modules/home/models/transaction_category.dart';
import 'package:mobile_app/modules/home/services/dashboard_service.dart';

class VaultScreen extends StatefulWidget {
  final String? initialFolderId;
  final String? initialSearch;
  const VaultScreen({super.key, this.initialFolderId, this.initialSearch});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  bool _isGridView = true;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final service = context.read<VaultService>();
      if (widget.initialSearch != null) {
        setState(() {
          _isSearching = true;
          _searchController.text = widget.initialSearch!;
        });
        service.fetchDocuments(search: widget.initialSearch);
      } else if (widget.initialFolderId != null) {
        service.navigateToFolder(widget.initialFolderId!, "Linked Folder");
      } else {
        service.fetchDocuments();
      }
    });
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
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
                icon: Icon(
                  vaultService.isSelectionMode ? Icons.close : Icons.arrow_back,
                ),
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
            ? Text(
                '${vaultService.selectedIds.length} Selected',
                style: const TextStyle(fontWeight: FontWeight.bold),
              )
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
                onChanged: (value) {
                  _searchTimer?.cancel();
                  _searchTimer = Timer(const Duration(milliseconds: 500), () {
                    vaultService.fetchDocuments(search: value);
                  });
                },
              )
            : const Text('Documents Vault'),
        actions: [
          if (vaultService.isSelectionMode) ...[
            IconButton(
              icon: const Icon(Icons.drive_file_move_outlined),
              onPressed: () =>
                  _showMovePicker(context, vaultService.selectedIds.toList()),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppTheme.danger),
              onPressed: () => _handleBulkDelete(context),
            ),
          ] else ...[
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
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child:
                      vaultService.isLoading && vaultService.documents.isEmpty
                      ? const Center(
                          key: ValueKey('loading'),
                          child: CircularProgressIndicator(),
                        )
                      : vaultService.error != null
                      ? _buildErrorState(vaultService.error!)
                      : filteredDocs.isEmpty
                      ? _buildEmptyState()
                      : KeyedSubtree(
                          key: ValueKey(
                            '${vaultService.currentParentId}_$_isGridView',
                          ),
                          child: _isGridView
                              ? _buildGridView(vaultService, filteredDocs)
                              : _buildListView(vaultService, filteredDocs),
                        ),
                ),
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                final result = await service.createFolder(controller.text);
                result.fold(
                  (failure) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(failure.message),
                        backgroundColor: AppTheme.danger,
                      ),
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
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.5),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: service.breadcrumbs.length,
        separatorBuilder: (context, index) =>
            const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
        itemBuilder: (context, index) {
          final crumb = service.breadcrumbs[index];
          final isLast = index == service.breadcrumbs.length - 1;

          return TextButton(
            onPressed: isLast
                ? null
                : () => service.navigateToBreadcrumb(index),
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
        content: const Text(
          'This action cannot be undone. All selected files and subfolders will be permanently removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(
                color: AppTheme.danger,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final result = await service.bulkDelete();
      result.fold(
        (failure) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(failure.message),
              backgroundColor: AppTheme.danger,
            ),
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
        children: types
            .map(
              (type) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  selected: vaultService.fileType == type,
                  label: Text(type, style: const TextStyle(fontSize: 10)),
                  onSelected: (selected) {
                    vaultService.setFileType(type);
                  },
                ),
              ),
            )
            .toList(),
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

        if (!mounted) return;
        final metadata = await _showUploadMetadataDialog(
          this.context,
          file.name,
        );
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
              SnackBar(
                content: Text('Upload error: ${failure.message}'),
                backgroundColor: AppTheme.danger,
              ),
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
          SnackBar(
            content: Text('Upload error: $e'),
            backgroundColor: AppTheme.danger,
          ),
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
            Text(
              error,
              style: const TextStyle(color: AppTheme.danger),
              textAlign: TextAlign.center,
            ),
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
            Icon(
              Icons.folder_open,
              size: 80,
              color: AppTheme.primary.withValues(alpha: 0.2),
            ),
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

  Map<String, List<VaultDocument>> _getGroupedDocs(
    List<VaultDocument> documents,
  ) {
    if (documents.isEmpty) return {};

    // Split folders and files
    final folders = documents.where((d) => d.isFolder).toList();
    final files = documents.where((d) => !d.isFolder).toList();

    final Map<String, List<VaultDocument>> grouped = {};

    if (folders.isNotEmpty) {
      grouped['Folders'] = folders;
    }

    // Sort files by date descending
    files.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    for (var doc in files) {
      final key = DateFormat('MMMM yyyy').format(doc.createdAt);
      if (!grouped.containsKey(key)) {
        grouped[key] = [];
      }
      grouped[key]!.add(doc);
    }

    return grouped;
  }

  Widget _buildSectionHeader(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Row(
        children: [
          Icon(
            title == 'Folders'
                ? Icons.folder_open
                : Icons.calendar_today_outlined,
            size: 14,
            color: AppTheme.primary,
          ),
          const SizedBox(width: 8),
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              color: AppTheme.primary.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Divider(
              color: AppTheme.primary.withValues(alpha: 0.1),
              thickness: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridView(VaultService service, List<VaultDocument> documents) {
    final grouped = _getGroupedDocs(documents);
    final keys = grouped.keys.toList();

    return CustomScrollView(
      slivers: [
        for (var key in keys) ...[
          SliverToBoxAdapter(child: _buildSectionHeader(key)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 0.82,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) =>
                    _buildDocCard(grouped[key]![index], service),
                childCount: grouped[key]!.length,
              ),
            ),
          ),
        ],
        const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
      ],
    );
  }

  Widget _buildListView(VaultService service, List<VaultDocument> documents) {
    final grouped = _getGroupedDocs(documents);
    final keys = grouped.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: keys.length,
      itemBuilder: (context, index) {
        final key = keys[index];
        final sectionDocs = grouped[key]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSectionHeader(key),
            ...sectionDocs.map((doc) => _buildDocTile(doc, service)),
          ],
        );
      },
    );
  }

  Widget _buildDocTile(VaultDocument doc, VaultService service) {
    final isSelected = service.selectedIds.contains(doc.id);
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected
            ? AppTheme.primary.withValues(alpha: 0.08)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: isSelected
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
        border: Border.all(
          color: isSelected
              ? AppTheme.primary
              : theme.dividerColor.withValues(alpha: 0.05),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        onTap: () {
          if (service.isSelectionMode) {
            service.toggleSelection(doc.id);
          } else {
            _handleTap(doc, service);
          }
        },
        onLongPress: () => service.toggleSelection(doc.id),
        leading: _buildFileIcon(doc, service, size: 44),
        title: Text(
          doc.filename,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 13,
            letterSpacing: -0.2,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            Text(
              doc.isFolder
                  ? 'Folder'
                  : (doc.linkedTransaction != null
                        ? doc.linkedTransaction!.description
                        : doc.fileType),
              style: TextStyle(
                fontSize: 10,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.6,
                ),
                fontWeight: FontWeight.bold,
              ),
            ),
            if (!doc.isFolder) ...[
              const Text(' • ', style: TextStyle(color: Colors.grey)),
              Text(
                doc.formattedSize,
                style: TextStyle(
                  fontSize: 9,
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.5,
                  ),
                ),
              ),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (doc.linkedTransaction != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '₹${doc.linkedTransaction!.amount.toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ),
            if (service.isSelectionMode)
              Checkbox(
                value: isSelected,
                onChanged: (_) => service.toggleSelection(doc.id),
                activeColor: AppTheme.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              )
            else
              IconButton(
                icon: const Icon(
                  Icons.more_vert,
                  size: 20,
                  color: Colors.black38,
                ),
                onPressed: () => _showActionSheet(doc, service),
              ),
          ],
        ),
      ),
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
          color: isSelected
              ? AppTheme.primary
              : theme.dividerColor.withValues(alpha: 0.1),
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
            gradient: isSelected
                ? LinearGradient(
                    colors: [
                      AppTheme.primary.withValues(alpha: 0.1),
                      AppTheme.primary.withValues(alpha: 0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : LinearGradient(
                    colors: [
                      theme.colorScheme.surface,
                      theme.colorScheme.surface.withValues(alpha: 0.8),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
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
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: Checkbox(
                            value: isSelected,
                            onChanged: (_) => service.toggleSelection(doc.id),
                            activeColor: AppTheme.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    if (!service.isSelectionMode)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: IconButton(
                          icon: const Icon(
                            Icons.more_vert,
                            size: 20,
                            color: Colors.black45,
                          ),
                          onPressed: () => _showActionSheet(doc, service),
                        ),
                      ),
                    if (doc.transactionId != null)
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.receipt_long_outlined,
                                size: 10,
                                color: Colors.white,
                              ),
                              if (doc.linkedTransaction != null) ...[
                                const SizedBox(width: 4),
                                Text(
                                  '₹${doc.linkedTransaction!.amount.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(12.0),
                color: theme.colorScheme.surface.withValues(
                  alpha: isSelected ? 0.0 : 0.8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          doc.isFolder
                              ? 'Folder'
                              : (doc.linkedTransaction != null
                                    ? doc.linkedTransaction!.description
                                    : doc.fileType),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.7),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          DateFormat('dd MMM').format(doc.createdAt),
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.5),
                            fontSize: 9,
                          ),
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

  Widget _buildFileIcon(
    VaultDocument doc,
    VaultService service, {
    required double size,
  }) {
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
          errorBuilder: (context, error, stackTrace) =>
              _buildPlaceholder(doc, size),
        ),
      );
    } else {
      content = _buildPlaceholder(doc, size);
    }

    return SizedBox(width: size, height: size, child: content);
  }

  Widget _buildPlaceholder(VaultDocument doc, double size) {
    IconData icon;
    Color color;

    final type = doc.fileType.toUpperCase();
    final mime = doc.mimeType?.toLowerCase() ?? '';

    if (mime.contains('pdf') || doc.filename.toLowerCase().endsWith('.pdf')) {
      icon = Icons.picture_as_pdf;
      color = Colors.redAccent;
    } else if (mime.startsWith('image/')) {
      icon = Icons.image_outlined;
      color = Colors.blueAccent;
    } else {
      switch (type) {
        case 'BILL':
          icon = Icons.receipt_long_outlined;
          color = Colors.teal;
          break;
        case 'INVOICE':
          icon = Icons.receipt_long;
          color = Colors.blue;
          break;
        case 'POLICY':
          icon = Icons.verified_user_outlined;
          color = Colors.green;
          break;
        case 'IDENTITY':
          icon = Icons.badge_outlined;
          color = Colors.indigo;
          break;
        case 'TAX':
          icon = Icons.account_balance_outlined;
          color = Colors.orange;
          break;
        default:
          icon = Icons.insert_drive_file_outlined;
          color = Colors.grey;
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: size * 0.6, color: color.withValues(alpha: 0.8)),
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
          child: Consumer<VaultService>(
            builder: (context, latestService, _) {
              // Find the latest version of this document to show updates (e.g. after linking)
              final latestDoc = latestService.documents.firstWhere(
                (d) => d.id == doc.id,
                orElse: () => doc,
              );

              return ListView(
                controller: scrollController,
                shrinkWrap: true,
                children: [
                  ListTile(
                    leading: _buildFileIcon(latestDoc, latestService, size: 32),
                    title: Text(
                      latestDoc.filename,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Text(
                      latestDoc.isFolder
                          ? 'Folder'
                          : '${latestDoc.fileType} • ${latestDoc.formattedSize}',
                    ),
                  ),
                  if (latestDoc.linkedTransaction != null) ...[
                    const Divider(indent: 16, endIndent: 16),
                    _buildTransactionInfo(latestDoc.linkedTransaction!),
                  ],
                  const Divider(),
                  if (!latestDoc.isFolder) ...[
                    ListTile(
                      leading: const Icon(Icons.remove_red_eye_outlined),
                      title: const Text('View Document'),
                      onTap: () {
                        Navigator.pop(context);
                        _openDocument(latestDoc, latestService);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.download_outlined),
                      title: const Text('Download'),
                      onTap: () async {
                        Navigator.pop(context);
                        final result = await latestService.saveDocument(
                          latestDoc,
                        );
                        result.fold(
                          (failure) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(failure.message),
                                backgroundColor: AppTheme.danger,
                              ),
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
                    onTap: () {
                      Navigator.pop(context);
                      _showDetailsDialog(context, latestDoc);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text('Rename'),
                    onTap: () {
                      Navigator.pop(context);
                      _showRenameDialog(context, latestDoc);
                    },
                  ),
                  ListTile(
                    leading: Icon(
                      latestDoc.linkedTransaction != null
                          ? Icons.link_off
                          : Icons.link,
                    ),
                    title: Text(
                      latestDoc.linkedTransaction != null
                          ? 'Unlink Transaction'
                          : 'Link to Transaction',
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      if (latestDoc.linkedTransaction != null) {
                        latestService.linkTransaction(latestDoc.id, null);
                      } else {
                        _showTransactionPicker(
                          context,
                          latestDoc.id,
                          latestService,
                        );
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.drive_file_move_outlined),
                    title: const Text('Move to Folder'),
                    onTap: () {
                      Navigator.pop(context);
                      _showMovePicker(context, [latestDoc.id]);
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.delete_outline,
                      color: AppTheme.danger,
                    ),
                    title: const Text(
                      'Delete',
                      style: TextStyle(color: AppTheme.danger),
                    ),
                    onTap: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Delete?'),
                          content: Text(
                            'Are you sure you want to delete ${latestDoc.filename}?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text(
                                'Delete',
                                style: TextStyle(color: AppTheme.danger),
                              ),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        final result = await latestService.deleteDocument(
                          latestDoc.id,
                        );
                        result.fold(
                          (failure) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(failure.message),
                                backgroundColor: AppTheme.danger,
                              ),
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
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildVaultSummary(VaultService service) {
    if (_isSearching) return const SizedBox.shrink();

    final totalSize = service.documents.fold<double>(
      0,
      (sum, doc) => sum + doc.fileSize,
    );
    final fileCount = service.documents.where((d) => !d.isFolder).length;
    final folderCount = service.documents.where((d) => d.isFolder).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary.withValues(alpha: 0.1),
            AppTheme.primary.withValues(alpha: 0.0),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Row(
        children: [
          _buildSummaryItem(
            Icons.insert_drive_file_outlined,
            '$fileCount Files',
          ),
          const SizedBox(width: 16),
          _buildSummaryItem(Icons.folder_outlined, '$folderCount Folders'),
          const Spacer(),
          _buildSummaryItem(
            Icons.storage,
            _formatSize(totalSize),
            color: AppTheme.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(IconData icon, String value, {Color? color}) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color ?? Colors.grey),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
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
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Move to Folder',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  ListTile(
                    leading: const Icon(Icons.home_outlined),
                    title: const Text(
                      'Root Vault',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onTap: () async {
                      final navigator = Navigator.of(context);
                      final result = await service.moveDocuments(
                        docIds,
                        'ROOT',
                      );
                      if (!mounted) return;
                      navigator.pop();
                      _handleActionResult(result, 'Moved successfully');
                    },
                  ),
                  const Divider(),
                  ...service.documents
                      .where((d) => d.isFolder && !docIds.contains(d.id))
                      .map(
                        (folder) => ListTile(
                          leading: const Icon(
                            Icons.folder_outlined,
                            color: Colors.amber,
                          ),
                          title: Text(
                            folder.filename,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onTap: () async {
                            final navigator = Navigator.of(context);
                            final result = await service.moveDocuments(
                              docIds,
                              folder.id,
                            );
                            if (!mounted) return;
                            navigator.pop();
                            _handleActionResult(
                              result,
                              'Moved to ${folder.filename}',
                            );
                          },
                        ),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTransactionPicker(
    BuildContext context,
    String docId,
    VaultService service,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        String query = "";
        return DraggableScrollableSheet(
          initialChildSize: 0.8,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) => Container(
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(25),
              ),
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
                Expanded(
                  child: StatefulBuilder(
                    builder: (context, setPickerState) {
                      return Column(
                        children: [
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
                                setPickerState(() => query = val);
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child:
                                FutureBuilder<Either<Failure, List<dynamic>>>(
                                  key: ValueKey(
                                    query,
                                  ), // Force rebuild on query change
                                  future: service.searchTransactions(
                                    query: query,
                                  ),
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState ==
                                        ConnectionState.waiting) {
                                      return const Center(
                                        child: CircularProgressIndicator(),
                                      );
                                    }
                                    return snapshot.data?.fold(
                                          (failure) => Center(
                                            child: Text(failure.message),
                                          ),
                                          (txns) {
                                            if (txns.isEmpty) {
                                              return const Center(
                                                child: Text(
                                                  'No transactions found',
                                                ),
                                              );
                                            }
                                            return ListView.builder(
                                              controller: scrollController,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                  ),
                                              itemCount: txns.length,
                                              itemBuilder: (context, index) {
                                                final txn = txns[index];
                                                return ListTile(
                                                  leading: CircleAvatar(
                                                    backgroundColor: AppTheme
                                                        .primary
                                                        .withValues(alpha: 0.1),
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
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: AppTheme.primary,
                                                      ),
                                                    ),
                                                  ),
                                                  title: Text(
                                                    txn['description'] ??
                                                        'No Description',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                  subtitle: Text(
                                                    txn['date'] ?? '',
                                                    style: const TextStyle(
                                                      fontSize: 10,
                                                    ),
                                                  ),
                                                  trailing: Text(
                                                    '₹${txn['amount']}',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      color: AppTheme.primary,
                                                    ),
                                                  ),
                                                  onTap: () async {
                                                    final result = await service
                                                        .linkTransaction(
                                                          docId,
                                                          txn['id'],
                                                        );
                                                    if (context.mounted) {
                                                      Navigator.pop(context);
                                                      _handleActionResult(
                                                        result,
                                                        'Linked successfully',
                                                      );
                                                    }
                                                  },
                                                );
                                              },
                                            );
                                          },
                                        ) ??
                                        const Center(
                                          child: Text(
                                            'Error loading transactions',
                                          ),
                                        );
                                  },
                                ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _handleActionResult(Either<Failure, Unit> result, String successMsg) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    result.fold(
      (failure) => messenger.showSnackBar(
        SnackBar(
          content: Text(failure.message),
          backgroundColor: AppTheme.danger,
        ),
      ),
      (_) => messenger.showSnackBar(SnackBar(content: Text(successMsg))),
    );
  }

  Widget _buildTransactionInfo(LinkedTransaction tx) {
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
              vertical: 0,
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

  Future<Map<String, String>?> _showUploadMetadataDialog(
    BuildContext context,
    String initialName,
  ) async {
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
                initialValue: type,
                decoration: const InputDecoration(labelText: 'Document Type'),
                items: ['OTHER', 'BILL', 'INVOICE', 'POLICY', 'TAX', 'IDENTITY']
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (val) => setDialogState(() => type = val!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, {
                'name': controller.text,
                'type': type,
              }),
              child: const Text('Proceed'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    VaultDocument doc,
  ) async {
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
                initialValue: type,
                decoration: const InputDecoration(labelText: 'Document Type'),
                items: ['OTHER', 'BILL', 'INVOICE', 'POLICY', 'TAX', 'IDENTITY']
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (val) => setDialogState(() => type = val!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (controller.text.isNotEmpty) {
                  final result = await service.updateDocumentMetadata(
                    doc.id,
                    newName: controller.text != doc.filename
                        ? controller.text
                        : null,
                    newType: type != doc.fileType.toUpperCase() ? type : null,
                  );
                  result.fold(
                    (failure) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(failure.message),
                          backgroundColor: AppTheme.danger,
                        ),
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
              SnackBar(
                content: Text(failure.message),
                backgroundColor: AppTheme.danger,
              ),
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
          SnackBar(
            content: Text('Could not open file: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  void _showDetailsDialog(BuildContext context, VaultDocument doc) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
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
                    const Icon(Icons.info_outline, color: AppTheme.primary),
                    const SizedBox(width: 12),
                    const Text(
                      'Document Details',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
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
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    _buildDetailRow('Filename', doc.filename),
                    _buildDetailRow('Type', doc.fileType),
                    if (!doc.isFolder)
                      _buildDetailRow('Size', doc.formattedSize),
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
                        _buildTransactionInfo(doc.linkedTransaction!)
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
        ),
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
