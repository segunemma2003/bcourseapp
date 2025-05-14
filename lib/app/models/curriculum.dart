import 'package:nylo_framework/nylo_framework.dart';

class Curriculum extends Model {
  final int id;
  final String title;
  final String videoUrl;
  final int order;

  static String storageKey = "curriculum";

  Curriculum({
    required this.id,
    required this.title,
    required this.videoUrl,
    required this.order,
  }) : super(key: storageKey);

  Curriculum.fromJson(dynamic data)
      : id = data['id'] ?? 0,
        title = data['title'] ?? '',
        videoUrl = data['video_url'] ?? '',
        order = data['order'] ?? 0,
        super(key: storageKey);

  @override
  toJson() {
    return {
      'id': id,
      'title': title,
      'video_url': videoUrl,
      'order': order,
    };
  }
}
