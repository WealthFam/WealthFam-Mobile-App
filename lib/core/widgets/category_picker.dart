import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_app/core/widgets/searchable_category_picker.dart';
import 'package:mobile_app/modules/home/services/categories_service.dart';

class CategoryPickerField extends StatelessWidget {
  final String selectedCategory;
  final Function(String) onCategorySelected;
  final bool isHighlighted;

  const CategoryPickerField({
    super.key,
    required this.selectedCategory,
    required this.onCategorySelected,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categoryService = context.watch<CategoriesService>();
    final categories = categoryService.categories;

    return InkWell(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => DraggableScrollableSheet(
            initialChildSize: 0.7,
            maxChildSize: 0.95,
            minChildSize: 0.5,
            builder: (_, controller) => SearchableCategoryPicker(
              categories: categories,
              selected: selectedCategory,
              onSelected: (cat) {
                onCategorySelected(cat);
                Navigator.pop(context);
              },
              scrollController: controller,
            ),
          ),
        );
      },
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isHighlighted ? theme.primaryColor.withOpacity(0.05) : theme.colorScheme.surface, 
          borderRadius: BorderRadius.circular(12), 
          border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
        ),
        child: Row(
          children: [
            Text(
              categories.any((c) => c.name == selectedCategory) 
                  ? (categories.firstWhere((c) => c.name == selectedCategory).icon ?? '🏷️') 
                  : (selectedCategory == 'Uncategorized' ? '📁' : '🏷️'),
              style: const TextStyle(fontSize: 16)
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                selectedCategory, 
                style: TextStyle(
                  fontSize: 13, 
                  fontWeight: FontWeight.bold,
                  color: isHighlighted ? theme.primaryColor : theme.colorScheme.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.search, size: 16, color: theme.colorScheme.onSurface.withOpacity(0.3)),
          ],
        ),
      ),
    );
  }
}
