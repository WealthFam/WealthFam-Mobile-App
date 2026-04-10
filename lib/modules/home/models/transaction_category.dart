class TransactionCategory {
  final String id;
  final String name;
  final String? icon;
  final String type;
  final String? parentId;
  final List<TransactionCategory> subcategories;

  TransactionCategory({
    required this.id,
    required this.name,
    this.icon,
    required this.type,
    this.parentId,
    this.subcategories = const [],
  });

  factory TransactionCategory.fromJson(Map<String, dynamic> json) {
    return TransactionCategory(
      id: json['id'],
      name: json['name'],
      icon: json['icon'],
      type: json['type'] ?? 'expense',
      parentId: json['parent_id'],
      subcategories: (json['subcategories'] as List?)
              ?.map((i) => TransactionCategory.fromJson(i))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'icon': icon,
      'type': type,
      'parent_id': parentId,
      'subcategories': subcategories.map((s) => s.toJson()).toList(),
    };
  }
}
