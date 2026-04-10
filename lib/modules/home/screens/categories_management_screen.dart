import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_app/modules/home/services/categories_service.dart';
import 'package:mobile_app/modules/home/models/transaction_category.dart';
import 'package:mobile_app/core/widgets/app_shell.dart';

class CategoriesManagementScreen extends StatefulWidget {
  const CategoriesManagementScreen({super.key});

  @override
  State<CategoriesManagementScreen> createState() => _CategoriesManagementScreenState();
}

class _CategoriesManagementScreenState extends State<CategoriesManagementScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CategoriesService>().fetchCategories();
    });
  }

  void _showCategoryForm({TransactionCategory? category, String? parentId}) {
    final nameCtrl = TextEditingController(text: category?.name ?? '');
    final iconCtrl = TextEditingController(text: category?.icon ?? '🏷️');
    String type = category?.type ?? 'expense';
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 16, right: 16, top: 16
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(category == null ? 'New Category' : 'Edit Category', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Category Name', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: iconCtrl,
                    decoration: const InputDecoration(labelText: 'Emoji Icon', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: type,
                    decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'expense', child: Text('Expense')),
                      DropdownMenuItem(value: 'income', child: Text('Income')),
                    ],
                    onChanged: (v) => setModalState(() => type = v!),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (category != null)
                        TextButton(
                          onPressed: () async {
                            final success = await context.read<CategoriesService>().deleteCategory(category.id);
                            if (success && mounted) Navigator.pop(context);
                          },
                          child: const Text('Delete', style: TextStyle(color: Colors.red)),
                        ),
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                      ElevatedButton(
                        onPressed: () async {
                          final service = context.read<CategoriesService>();
                          bool success;
                          if (category == null) {
                            success = await service.createCategory(nameCtrl.text, type, icon: iconCtrl.text, parentId: parentId);
                          } else {
                            success = await service.updateCategory(category.id, nameCtrl.text, type, icon: iconCtrl.text, parentId: parentId);
                          }
                          if (success && mounted) Navigator.pop(context);
                        },
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            );
          }
        );
      }
    );
  }

  Widget _buildCategoryNode(TransactionCategory category, ThemeData theme, {int depth = 0}) {
    final hasChildren = category.subcategories.isNotEmpty;
    final padding = EdgeInsets.only(left: 16.0 + (depth * 24.0), right: 16.0);

    final leading = CircleAvatar(
      backgroundColor: category.type == 'income' ? Colors.green.withOpacity(0.1) : theme.primaryColor.withOpacity(0.1),
      child: Text(category.icon ?? category.name[0].toUpperCase(), style: const TextStyle(fontSize: 18)),
    );

    final title = Text(category.name, style: TextStyle(fontWeight: depth == 0 ? FontWeight.bold : FontWeight.w500));
    final subtitle = Text(category.type.toUpperCase(), style: const TextStyle(fontSize: 10));

    final trailing = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(icon: const Icon(Icons.add_circle_outline, size: 20), onPressed: () => _showCategoryForm(parentId: category.id)),
        IconButton(icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _showCategoryForm(category: category, parentId: category.parentId)),
        if (hasChildren) const Icon(Icons.expand_more, size: 20),
      ],
    );

    if (!hasChildren) {
      return ListTile(
        contentPadding: padding,
        leading: leading,
        title: title,
        subtitle: subtitle,
        trailing: trailing,
      );
    }

    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: padding,
        leading: leading,
        title: title,
        subtitle: subtitle,
        trailing: trailing,
        initiallyExpanded: depth == 0, // Expand top level by default
        children: category.subcategories.map((child) => _buildCategoryNode(child, theme, depth: depth + 1)).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categoriesService = context.watch<CategoriesService>();
    final theme = Theme.of(context);

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: const DrawerMenuButton(),
        title: const Text('Categories & Hierarchy'),
      ),
      body: categoriesService.isLoading && categoriesService.categories.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => categoriesService.fetchCategories(force: true),
              child: categoriesService.categories.isEmpty
                  ? ListView(
                      children: [
                        SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                        const Center(child: Text('No categories found')),
                      ],
                    )
                  : ListView.separated(
                      itemCount: categoriesService.categories.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final category = categoriesService.categories[index];
                        return _buildCategoryNode(category, theme);
                      },
                    ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCategoryForm(),
        icon: const Icon(Icons.add),
        label: const Text("New Category"),
      ),
    );
  }
}
