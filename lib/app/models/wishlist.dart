import 'package:nylo_framework/nylo_framework.dart';

class Wishlist extends Model {
  static StorageKey key = "wishlist";

  final int id;
  final int courseId;
  final String courseTitle;
  final String courseImage;
  final String dateAdded;

  Wishlist({
    required this.id,
    required this.courseId,
    required this.courseTitle,
    required this.courseImage,
    required this.dateAdded,
  }) : super(key: key);

  Wishlist.fromJson(Map<String, dynamic> data)
      : id = data['id'] ?? 0,
        courseId = data['course'] ?? 0,
        courseTitle = data['course_title'] ?? 'Untitled Course',
        courseImage = data['course_image'] ?? '',
        dateAdded = data['date_added'] ?? '',
        super(key: key);

  @override
  toJson() {
    return {
      'id': id,
      'course': courseId,
      'course_title': courseTitle,
      'course_image': courseImage,
      'date_added': dateAdded,
    };
  }

  // Helper method to create Course object from Wishlist
  String get courseIdString => courseId.toString();
}
