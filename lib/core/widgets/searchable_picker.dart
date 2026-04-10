import 'package:flutter/material.dart';

class SearchablePicker extends StatelessWidget {
  final String title;
  final String? label;
  final String? placeholder;
  final List<dynamic> items;
  final String Function(dynamic) labelMapper;
  final String? Function(dynamic)? iconMapper;
  final dynamic selectedValue;
  final Function(dynamic) onSelected;
  final bool isHighlighted;
  final Color? highlightColor;

  const SearchablePicker({
    super.key,
    required this.title,
    this.label,
    this.placeholder,
    required this.items,
    required this.labelMapper,
    this.iconMapper,
    required this.onSelected,
    this.selectedValue,
    this.isHighlighted = false,
    this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayLabel = selectedValue != null ? labelMapper(selectedValue) : (placeholder ?? 'Select...');

    return InkWell(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => SearchablePickerModal(
            title: title,
            items: items,
            onSelected: onSelected,
            labelMapper: labelMapper,
            iconMapper: iconMapper,
          ),
        );
      },
      child: Container(
        height: 48, // More compact
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isHighlighted ? (highlightColor ?? theme.primaryColor.withOpacity(0.05)) : theme.colorScheme.surface, 
          borderRadius: BorderRadius.circular(12), 
          border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
        ),
        child: Row(
          children: [
            if (selectedValue != null && iconMapper != null) ...[
               Text(iconMapper!(selectedValue) ?? '', style: const TextStyle(fontSize: 16)),
               const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                displayLabel, 
                style: TextStyle(
                  fontSize: 13, 
                  fontWeight: selectedValue != null ? FontWeight.bold : FontWeight.normal,
                  color: isHighlighted ? theme.primaryColor : (selectedValue != null ? theme.colorScheme.onSurface : theme.colorScheme.onSurface.withOpacity(0.5)),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.keyboard_arrow_down, size: 18, color: theme.colorScheme.onSurface.withOpacity(0.3)),
          ],
        ),
      ),
    );
  }
}

class SearchablePickerModal extends StatefulWidget {
  final String title;
  final List<dynamic> items;
  final Function(dynamic) onSelected;
  final String Function(dynamic) labelMapper;
  final String? Function(dynamic)? iconMapper;

  const SearchablePickerModal({
    super.key,
    required this.title,
    required this.items,
    required this.onSelected,
    required this.labelMapper,
    this.iconMapper,
  });

  @override
  State<SearchablePickerModal> createState() => _SearchablePickerModalState();
}

class _SearchablePickerModalState extends State<SearchablePickerModal> {
  late List<dynamic> _filteredItems;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filteredItems = widget.items;
  }

  void _filter(String q) {
    setState(() {
      _filteredItems = widget.items.where((i) {
        return widget.labelMapper(i).toLowerCase().contains(q.toLowerCase());
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: theme.dividerColor, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Text(widget.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                const Spacer(),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: theme.colorScheme.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
              onChanged: _filter,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: _filteredItems.length,
              itemBuilder: (context, index) {
                final item = _filteredItems[index];
                final label = widget.labelMapper(item);
                final icon = widget.iconMapper?.call(item);
                
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                  leading: icon != null ? Text(icon, style: const TextStyle(fontSize: 20)) : const Icon(Icons.blur_on),
                  title: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
                  onTap: () {
                    widget.onSelected(item);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
