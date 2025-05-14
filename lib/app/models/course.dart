import 'package:nylo_framework/nylo_framework.dart';

class Course extends Model {
  final int id;
  final String title;
  final String image;
  final String smallDesc;
  final String description;
  final int category;
  final String categoryName;
  final bool isFeatured;
  final String dateUploaded;
  final String location;
  final int enrolledStudents;
  final bool isEnrolled;
  final bool isWishlisted;
  final List<CourseObjective> objectives;
  final List<CourseRequirement> requirements;
  final List<CourseCurriculum> curriculum;

  static String storageKey = "course";

  Course({
    required this.id,
    required this.title,
    required this.image,
    required this.description,
    required this.smallDesc,
    required this.category,
    required this.categoryName,
    required this.location,
    this.isFeatured = false,
    this.dateUploaded = '',
    this.enrolledStudents = 0,
    this.isEnrolled = false,
    this.isWishlisted = false,
    this.objectives = const [],
    this.requirements = const [],
    this.curriculum = const [],
  }) : super(key: storageKey);

  Course.fromJson(dynamic data)
      : id = data['id'] ?? 0,
        title = data['title'] ?? '',
        image = data['image'] ?? '',
        smallDesc = data['small_desc'] ?? '',
        description = data['description'] ?? '',
        category = data['category'] ?? 0,
        categoryName = data['category_name'] ?? '',
        isFeatured = data['is_featured'] ?? false,
        dateUploaded = data['date_uploaded'] ?? '',
        location = data['location'] ?? '',
        enrolledStudents =
            int.tryParse(data['enrolled_students']?.toString() ?? '0') ?? 0,
        isEnrolled =
            data['is_enrolled'] == 'true' || data['is_enrolled'] == true,
        isWishlisted =
            data['is_wishlisted'] == 'true' || data['is_wishlisted'] == true,
        objectives = (data['objectives'] ?? [])
            .map<CourseObjective>((obj) => CourseObjective.fromJson(obj))
            .toList(),
        requirements = (data['requirements'] ?? [])
            .map<CourseRequirement>((req) => CourseRequirement.fromJson(req))
            .toList(),
        curriculum = (data['curriculum'] ?? [])
            .map<CourseCurriculum>((cur) => CourseCurriculum.fromJson(cur))
            .toList(),
        super(key: storageKey);

  @override
  toJson() {
    return {
      'id': id,
      'title': title,
      'image': image,
      'small_desc': smallDesc,
      'category': category,
      'category_name': categoryName,
      'is_featured': isFeatured,
      'date_uploaded': dateUploaded,
      'location': location,
      'enrolled_students': enrolledStudents,
      'is_enrolled': isEnrolled.toString(),
      'is_wishlisted': isWishlisted.toString(),
      'objectives': objectives.map((obj) => obj.toJson()).toList(),
      'requirements': requirements.map((req) => req.toJson()).toList(),
      'curriculum': curriculum.map((cur) => cur.toJson()).toList(),
    };
  }
}

class CourseObjective extends Model {
  final int id;
  final String description;

  static String storageKey = "course_objective";

  CourseObjective({
    required this.id,
    required this.description,
  }) : super(key: storageKey);

  CourseObjective.fromJson(dynamic data)
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

class CourseRequirement extends Model {
  final int id;
  final String description;

  static String storageKey = "course_requirement";

  CourseRequirement({
    required this.id,
    required this.description,
  }) : super(key: storageKey);

  CourseRequirement.fromJson(dynamic data)
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

class CourseCurriculum extends Model {
  final int id;
  final String title;
  final String videoUrl;
  final int order;

  static String storageKey = "course_curriculum";

  CourseCurriculum({
    required this.id,
    required this.title,
    required this.videoUrl,
    this.order = 0,
  }) : super(key: storageKey);

  CourseCurriculum.fromJson(dynamic data)
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
