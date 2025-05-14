import 'package:nylo_framework/nylo_framework.dart';

class Requirements extends Model {
  final int id;
  final String description;

  static String storageKey = "requirements";

  Requirements({
    required this.id,
    required this.description,
  }) : super(key: storageKey);

  Requirements.fromJson(dynamic data)
      : id = data['id'] ?? 0,
        description = data['description'] ?? '',
        super(key: storageKey);

  @override
  toJson() {
    return {
      'id': id,
      'description': description,
    };
  }
}
