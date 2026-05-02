import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_app/core/theme/app_theme.dart';
import 'package:mobile_app/modules/vault/services/vault_service.dart';

class VaultFileIcon extends StatelessWidget {
  const VaultFileIcon({
    required this.doc,
    required this.service,
    required this.size,
    super.key,
  });

  final VaultDocument doc;
  final VaultService service;
  final double size;

  @override
  Widget build(BuildContext context) {
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
              VaultFilePlaceholder(doc: doc, size: size),
        ),
      );
    } else {
      content = VaultFilePlaceholder(doc: doc, size: size);
    }

    return SizedBox(width: size, height: size, child: content);
  }
}

class VaultFilePlaceholder extends StatelessWidget {
  const VaultFilePlaceholder({
    required this.doc,
    required this.size,
    super.key,
  });

  final VaultDocument doc;
  final double size;

  @override
  Widget build(BuildContext context) {
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
}

class VaultListItem extends StatelessWidget {
  const VaultListItem({
    required this.doc,
    required this.service,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
    required this.onMorePressed,
    super.key,
  });

  final VaultDocument doc;
  final VaultService service;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMorePressed;

  @override
  Widget build(BuildContext context) {
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
        onTap: onTap,
        onLongPress: onLongPress,
        leading: VaultFileIcon(doc: doc, service: service, size: 44),
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
                onPressed: onMorePressed,
              ),
          ],
        ),
      ),
    );
  }
}

class VaultGridItem extends StatelessWidget {
  const VaultGridItem({
    required this.doc,
    required this.service,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
    required this.onMorePressed,
    super.key,
  });

  final VaultDocument doc;
  final VaultService service;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMorePressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
        onTap: onTap,
        onLongPress: onLongPress,
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
                    VaultFileIcon(doc: doc, service: service, size: 64),
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
                          onPressed: onMorePressed,
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
}
