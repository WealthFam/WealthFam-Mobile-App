import 'package:flutter/material.dart';
import 'package:mobile_app/modules/home/models/transaction_category.dart';
import 'package:mobile_app/core/theme/app_theme.dart';

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
    this.scrollController
  });

  @override
  State<SearchableCategoryPicker> createState() => _SearchableCategoryPickerState();
}

class _SearchableCategoryPickerState extends State<SearchableCategoryPicker> {
  String _searchQuery = "";
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final List<TransactionCategory> filteredDisplay = [];
    
    for (var parent in widget.categories) {
      final bool parentMatches = parent.name.toLowerCase().contains(_searchQuery.toLowerCase());
      final List<TransactionCategory> matchingSubs = parent.subcategories.where((s) => s.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
      
      if (parentMatches || matchingSubs.isNotEmpty) {
        if (_searchQuery.isNotEmpty) {
          if (parentMatches) filteredDisplay.add(parent);
          filteredDisplay.addAll(matchingSubs);
        } else {
          filteredDisplay.add(parent);
          filteredDisplay.addAll(parent.subcategories);
        }
      }
    }

    return Container(
      decoration: BoxDecoration(color: theme.scaffoldBackgroundColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: theme.dividerColor.withOpacity(0.1), borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Search categories...', 
                      prefixIcon: const Icon(Icons.search), 
                      filled: true, 
                      fillColor: theme.colorScheme.surface, 
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(100), borderSide: BorderSide.none)
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: () => Navigator.pop(context), 
                  icon: const Icon(Icons.close),
                  style: IconButton.styleFrom(backgroundColor: theme.colorScheme.surface),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: widget.scrollController,
              itemCount: filteredDisplay.length,
              itemBuilder: (context, index) {
                final cat = filteredDisplay[index];
                final bool isSub = cat.parentId != null;
                String? parentName;
                if (isSub) {
                   try {
                     parentName = widget.categories.firstWhere((p) => p.id == cat.parentId).name;
                   } catch (_) {
                     parentName = 'Parent';
                   }
                }

                if (!isSub && _searchQuery.isEmpty) {
                   return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(padding: const EdgeInsets.fromLTRB(24, 16, 24, 8), child: Text(cat.name.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: theme.primaryColor, letterSpacing: 1.2))),
                    _buildCatTile(cat, isSub: false),
                   ]);
                }
                return _buildCatTile(cat, isSub: isSub, parentName: parentName);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCatTile(TransactionCategory cat, {bool isSub = false, String? parentName}) {
    final isSelected = widget.selected == cat.name;
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      leading: Padding(padding: EdgeInsets.only(left: isSub ? 16 : 0), child: Text(cat.icon ?? (isSub ? '🔹' : '🏷️'), style: TextStyle(fontSize: isSub ? 14 : 18))),
      title: Text(isSub && _searchQuery.isNotEmpty ? '${parentName!} > ${cat.name}' : cat.name, style: TextStyle(fontWeight: isSelected ? FontWeight.w900 : (isSub ? FontWeight.w500 : FontWeight.bold), fontSize: isSub ? 13 : 14, color: isSub ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.onSurface)),
      trailing: isSelected ? const Icon(Icons.check_circle, color: AppTheme.success, size: 20) : null,
      onTap: () => widget.onSelected(cat.name),
    );
  }
}
