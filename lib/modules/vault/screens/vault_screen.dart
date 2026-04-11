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
  String _selectedType = 'ALL';

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
    
    final filteredDocs = vaultService.documents.where((doc) {
      if (_selectedType == 'ALL') return true;
      return doc.fileType.toUpperCase() == _selectedType;
    }).toList();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: vaultService.canGoBack 
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => vaultService.goBack(),
            )
          : const DrawerMenuButton(),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Documents Vault'),
            if (vaultService.canGoBack)
              Text(
                'Folder: ${vaultService.currentParentId.substring(0, 8)}...',
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_isGridView ? Icons.list : Icons.grid_view),
            onPressed: () => setState(() => _isGridView = !_isGridView),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => vaultService.fetchDocuments(),
        child: vaultService.isLoading && vaultService.documents.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _buildFilterBar(),
                  Expanded(
                    child: vaultService.error != null
                        ? _buildErrorState(vaultService.error!)
                        : filteredDocs.isEmpty
                            ? _buildEmptyState()
                            : _isGridView 
                                ? _buildGridView(vaultService, filteredDocs)
                                : _buildListView(vaultService, filteredDocs),
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
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Upload File'),
              onTap: () {
                Navigator.pop(context);
                _pickAndUpload(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder),
              title: const Text('New Folder'),
              onTap: () {
                Navigator.pop(context);
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
                    ScaffoldMessenger.of(context).showSnackBar(
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

  Future<void> _showRenameDialog(BuildContext context, VaultDocument doc) async {
    final controller = TextEditingController(text: doc.filename);
    final service = context.read<VaultService>();

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'New Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              if (controller.text.isNotEmpty && controller.text != doc.filename) {
                final result = await service.renameDocument(doc.id, controller.text);
                result.fold(
                  (failure) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(failure.message), backgroundColor: AppTheme.danger),
                    );
                  },
                  (_) {
                    if (mounted) Navigator.pop(context);
                  },
                );
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    final types = ['ALL', 'INVOICE', 'POLICY', 'TAX', 'IDENTITY', 'OTHER'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: types.map((type) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilterChip(
            selected: _selectedType == type,
            label: Text(type, style: const TextStyle(fontSize: 10)),
            onSelected: (selected) {
              setState(() => _selectedType = type);
              // In a real app, you'd trigger a filtered fetch here
            },
          ),
        )).toList(),
      ),
    );
  }

  Future<void> _pickAndUpload(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final file = result.files.single;
        final service = context.read<VaultService>();
        
        final uploadResult = await service.uploadDocument(
          filePath: file.path!,
          fileName: file.name,
        );

        uploadResult.fold(
          (failure) {
             ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Upload error: ${failure.message}'), backgroundColor: AppTheme.danger),
            );
          },
          (_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Uploaded ${file.name}')),
              );
            }
          },
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload error: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: AppTheme.danger),
          const SizedBox(height: 16),
          Text(error, style: const TextStyle(color: AppTheme.danger)),
          TextButton(
            onPressed: () => context.read<VaultService>().fetchDocuments(),
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
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
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: _buildFileIcon(doc, service, size: 40),
            title: Text(doc.filename, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${doc.isFolder ? 'Folder' : doc.fileType} • ${doc.formattedSize}'),
            trailing: IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () => _showActionSheet(doc, service),
            ),
            onTap: () => _handleTap(doc, service),
          ),
        );
      },
    );
  }

  Widget _buildDocCard(VaultDocument doc, VaultService service) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: InkWell(
        onTap: () => _handleTap(doc, service),
        onLongPress: () => _showActionSheet(doc, service),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildFileIcon(doc, service, size: 64),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton(
                      icon: const Icon(Icons.more_vert, size: 20, color: Colors.white70),
                      onPressed: () => _showActionSheet(doc, service),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8.0),
              color: theme.colorScheme.surface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doc.filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        doc.isFolder ? 'Folder' : doc.fileType,
                        style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 10),
                      ),
                      Text(
                        DateFormat('dd MMM').format(doc.createdAt),
                        style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withOpacity(0.6), fontSize: 9),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileIcon(VaultDocument doc, VaultService service, {required double size}) {
    final theme = Theme.of(context);
    
    if (doc.isFolder) {
      return Center(
        child: Icon(Icons.folder, size: size, color: Colors.amber),
      );
    }

    if (doc.thumbnailPath != null) {
      return Image.network(
        service.getThumbnailUrl(doc.id),
        headers: service.authHeaders,
        fit: BoxFit.cover,
        errorBuilder: (context, _, __) => _buildPlaceholder(doc, size),
      );
    }

    return _buildPlaceholder(doc, size);
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
      color: color.withOpacity(0.1),
      child: Center(
        child: Icon(icon, size: size, color: color.withOpacity(0.8)),
      ),
    );
  }

  void _handleTap(VaultDocument doc, VaultService service) {
    if (doc.isFolder) {
      service.navigateToFolder(doc.id);
    } else {
      _showActionSheet(doc, service);
    }
  }

  void _showActionSheet(VaultDocument doc, VaultService service) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: _buildFileIcon(doc, service, size: 32),
              title: Text(doc.filename),
              subtitle: Text(doc.isFolder ? 'Folder' : '${doc.fileType} • ${doc.formattedSize}'),
            ),
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(failure.message), backgroundColor: AppTheme.danger),
                      );
                    },
                    (path) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Saved to: $path')),
                        );
                      }
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(failure.message), backgroundColor: AppTheme.danger),
                      );
                    },
                    (_) {
                      if (mounted) Navigator.pop(context);
                    },
                  );
                }
              },
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
