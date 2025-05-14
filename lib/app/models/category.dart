import 'package:nylo_framework/nylo_framework.dart';

class Category extends Model {
  final int id;
  final String name;
  final String imageUrl;
  final String description;

  static String storageKey = "category";

  Category({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.description,
  }) : super(key: storageKey);

  Category.fromJson(dynamic data)
      : id = data['id'] ?? 0,
        name = data['name'] ?? '',
        imageUrl = data['image_url'] ?? '',
        description = data['description'] ?? '',
        super(key: storageKey);

  @override
  toJson() {
    return {
      'id': id,
      'name': name,
      'image_url': imageUrl,
      'description': description,
    };
  }
}
