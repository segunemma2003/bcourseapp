import 'package:nylo_framework/nylo_framework.dart';

class Objectives extends Model {
  final int id;
  final String description;

  static String storageKey = "objectives";

  Objectives({
    required this.id,
    required this.description,
  }) : super(key: storageKey);

  Objectives.fromJson(dynamic data)
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
