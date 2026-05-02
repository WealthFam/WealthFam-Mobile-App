import 'package:flutter/material.dart';
import 'package:mobile_app/modules/home/models/transaction_category.dart';

class SearchableCategoryPicker extends StatefulWidget {
  final List<TransactionCategory> categories;
  final String selected;
  final Function(String) onSelected;
  final ScrollController? scrollController;

  const SearchableCategoryPicker({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelected,
    this.scrollController,
  });

  @override
  State<SearchableCategoryPicker> createState() =>
      _SearchableCategoryPickerState();
}

class _SearchableCategoryPickerState extends State<SearchableCategoryPicker> {
  String _searchQuery = "";

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final List<TransactionCategory> filteredDisplay = [];

    for (var parent in widget.categories) {
      final bool parentMatches = parent.name.toLowerCase().contains(
        _searchQuery.toLowerCase(),
      );
      final List<TransactionCategory> matchingSubs = parent.subcategories
          .where(
            (s) => s.name.toLowerCase().contains(_searchQuery.toLowerCase()),
          )
          .toList();

      if (parentMatches || matchingSubs.isNotEmpty) {
        if (_searchQuery.isNotEmpty) {
          if (parentMatches) {
            filteredDisplay.add(parent);
          }
          filteredDisplay.addAll(matchingSubs);
        } else {
          filteredDisplay.add(parent);
          filteredDisplay.addAll(parent.subcategories);
        }
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.dividerColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Search categories...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(100),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 20),
                  style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.surface,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: widget.scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                if (_searchQuery.isEmpty)
                  _buildSectionHeader(theme, 'ALL CATEGORIES'),

                ...widget.categories.where((c) => c.parentId == null).map((
                  parent,
                ) {
                  final matchingSubs = parent.subcategories
                      .where(
                        (s) => s.name.toLowerCase().contains(
                          _searchQuery.toLowerCase(),
                        ),
                      )
                      .toList();
                  final bool parentMatches = parent.name.toLowerCase().contains(
                    _searchQuery.toLowerCase(),
                  );

                  if (!parentMatches && matchingSubs.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  // Only show as a section if there are actually subcategories
                  final bool hasSubcategories = parent.subcategories.isNotEmpty;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hasSubcategories && _searchQuery.isEmpty)
                        _buildParentHeader(theme, parent),

                      if (parentMatches) _buildCatTile(parent, isSub: false),

                      ...matchingSubs.map(
                        (sub) => _buildCatTile(
                          sub,
                          isSub: true,
                          parentName: parent.name,
                        ),
                      ),

                      if (_searchQuery.isEmpty && hasSubcategories)
                        const SizedBox(height: 12),
                    ],
                  );
                }),

                const SizedBox(height: 48),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: theme.disabledColor,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildParentHeader(ThemeData theme, TransactionCategory parent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Text(
        parent.name.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: theme.primaryColor.withValues(alpha: 0.6),
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildCatTile(
    TransactionCategory cat, {
    bool isSub = false,
    String? parentName,
  }) {
    final fullPath = isSub ? '$parentName › ${cat.name}' : cat.name;
    final isSelected =
        widget.selected.toLowerCase().trim() == fullPath.toLowerCase().trim() ||
        (isSub &&
            widget.selected.toLowerCase().trim() ==
                cat.name.toLowerCase().trim());

    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.only(left: isSub ? 28 : 12, right: 12),
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        tileColor: isSelected
            ? theme.primaryColor.withValues(alpha: 0.05)
            : null,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSub)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  '└',
                  style: TextStyle(color: theme.disabledColor, fontSize: 14),
                ),
              ),
            Text(
              cat.icon ?? (isSub ? '🔹' : '🏷️'),
              style: TextStyle(fontSize: isSub ? 16 : 18),
            ),
          ],
        ),
        title: Text(
          isSub && _searchQuery.isNotEmpty ? fullPath : cat.name,
          style: TextStyle(
            fontWeight: isSelected
                ? FontWeight.w900
                : (isSub || _searchQuery.isNotEmpty
                      ? FontWeight.w500
                      : FontWeight.bold),
            fontSize: isSub ? 13 : 14,
            color: isSelected
                ? theme.primaryColor
                : (isSub
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.onSurface),
          ),
        ),
        trailing: isSelected
            ? Icon(Icons.check_circle, color: theme.primaryColor, size: 18)
            : null,
        onTap: () => widget.onSelected(fullPath),
      ),
    );
  }
}
