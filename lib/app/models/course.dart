import 'package:nylo_framework/nylo_framework.dart';

class SimplerCourse extends Model {
  final int id;
  final String title;
  final String image;
  final String smallDesc;
  final String categoryName;

  static String storageKey = "simpler_course";

  SimplerCourse({
    required this.id,
    required this.title,
    required this.image,
    required this.smallDesc,
    required this.categoryName,
  }) : super(key: storageKey);

  SimplerCourse.fromJson(dynamic data)
      : id = data['id'] ?? 0,
        title = data['title'] ?? '',
        image = data['image'] ?? '',
        smallDesc = data['small_desc'] ?? '',
        categoryName = data['category_name'] ?? '',
        super(key: storageKey);

  @override
  toJson() {
    return {
      'id': id,
      'title': title,
      'image': image,
      'small_desc': smallDesc,
      'category_name': categoryName,
    };
  }
}

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
  final String priceOneMonth;
  final String priceThreeMonths;
  final String priceLifetime;
  final String location;
  final int enrolledStudents;
  final bool isEnrolled;
  final bool isWishlisted;
  final List<CourseObjective> objectives;
  final List<CourseRequirement> requirements;
  final List<CourseCurriculum> curriculum;

  // Enrollment status fields
  final UserEnrollment? userEnrollment;
  final EnrollmentStatus? enrollmentStatus;

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
    this.priceOneMonth = '999',
    this.priceThreeMonths = '2499',
    this.priceLifetime = '4999',
    this.isFeatured = false,
    this.dateUploaded = '',
    this.enrolledStudents = 0,
    this.isEnrolled = false,
    this.isWishlisted = false,
    this.objectives = const [],
    this.requirements = const [],
    this.curriculum = const [],
    this.userEnrollment,
    this.enrollmentStatus,
  }) : super(key: storageKey);

  Course.fromJson(dynamic data)
      : id = data['id'] ?? 0,
        title = data['title'] ?? '',
        image = data['image'] ?? '',
        smallDesc = data['small_desc'] ?? '',
        description = data['description'] ?? '',
        category = data['category'] ?? 0,
        categoryName = data['category_name'] ?? '',
        priceOneMonth = data['price_one_month'] ?? '999',
        priceThreeMonths = data['price_three_months'] ?? '2499',
        priceLifetime = data['price_lifetime'] ?? '4999',
        dateUploaded = data['date_uploaded'] ?? '',
        location = data['location'] ?? '',
        enrolledStudents =
            int.tryParse(data['enrolled_students']?.toString() ?? '0') ?? 0,
        isEnrolled = _parseBool(data['is_enrolled']),
        isWishlisted = _parseBool(data['is_wishlisted']),
        isFeatured = _parseBool(data['is_featured']),
        objectives = (data['objectives'] ?? [])
            .map<CourseObjective>((obj) => CourseObjective.fromJson(obj))
            .toList(),
        requirements = (data['requirements'] ?? [])
            .map<CourseRequirement>((req) => CourseRequirement.fromJson(req))
            .toList(),
        curriculum = (data['curriculum'] ?? [])
            .map<CourseCurriculum>((cur) => CourseCurriculum.fromJson(cur))
            .toList(),
        // Parse enrollment status information
        userEnrollment = data['user_enrollment'] != null
            ? UserEnrollment.fromJson(data['user_enrollment'])
            : null,
        enrollmentStatus = data['enrollment_status'] != null
            ? EnrollmentStatus.fromJson(data['enrollment_status'])
            : null,
        super(key: storageKey);

  @override
  toJson() {
    return {
      'id': id,
      'title': title,
      'image': image,
      'small_desc': smallDesc,
      'description': description,
      'category': category,
      'category_name': categoryName,
      'price_one_month': priceOneMonth,
      'price_three_months': priceThreeMonths,
      'price_lifetime': priceLifetime,
      'is_featured': isFeatured,
      'date_uploaded': dateUploaded,
      'location': location,
      'enrolled_students': enrolledStudents,
      'is_enrolled': isEnrolled.toString(),
      'is_wishlisted': isWishlisted.toString(),
      'objectives': objectives.map((obj) => obj.toJson()).toList(),
      'requirements': requirements.map((req) => req.toJson()).toList(),
      'curriculum': curriculum.map((cur) => cur.toJson()).toList(),
      'user_enrollment': userEnrollment?.toJson(),
      'enrollment_status': enrollmentStatus?.toJson(),
    };
  }

  static bool _parseBool(dynamic value) {
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    if (value is int) return value == 1;
    return false;
  }

  // ✅ FIXED: Add extensive debugging to find the issue
  bool get hasValidSubscription {
    NyLogger.info('🔍 DEBUG hasValidSubscription for course $id ($title):');
    NyLogger.info('   isEnrolled: $isEnrolled');
    NyLogger.info('   enrollmentStatus: ${enrollmentStatus?.toJson()}');
    NyLogger.info('   userEnrollment: ${userEnrollment?.toJson()}');

    // If not enrolled, no valid subscription
    if (!isEnrolled) {
      NyLogger.info('   ❌ Not enrolled, returning false');
      return false;
    }

    // Check if it's a lifetime subscription
    if (isLifetimeSubscription) {
      NyLogger.info('   ✅ Lifetime subscription, returning true');
      return true;
    }

    // Get expiry date
    DateTime? expiryDate = subscriptionExpiryDate;

    if (expiryDate == null) {
      NyLogger.info('   ✅ No expiry date found, assuming valid since enrolled');
      return true;
    }

    // Compare with current date
    DateTime now = DateTime.now();
    DateTime expiryDateOnly =
        DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
    DateTime nowDateOnly = DateTime(now.year, now.month, now.day);

    bool isValid = nowDateOnly.isBefore(expiryDateOnly) ||
        nowDateOnly.isAtSameMomentAs(expiryDateOnly);

    NyLogger.info('   📅 Current date: ${nowDateOnly.toString()}');
    NyLogger.info('   📅 Expiry date: ${expiryDateOnly.toString()}');
    NyLogger.info('   ✅ Subscription valid: $isValid');

    return isValid;
  }

  bool get isLifetimeSubscription {
    if (enrollmentStatus != null) {
      return enrollmentStatus!.isLifetime;
    }

    if (userEnrollment != null) {
      return userEnrollment!.planType == 'LIFETIME';
    }

    return false;
  }

  DateTime? get subscriptionExpiryDate {
    if (enrollmentStatus != null) {
      return enrollmentStatus!.expiresOn;
    }

    if (userEnrollment != null) {
      return userEnrollment!.expiryDate;
    }

    return null;
  }

  String get subscriptionPlanName {
    if (enrollmentStatus != null) {
      return enrollmentStatus!.planName;
    }

    if (userEnrollment != null) {
      return userEnrollment!.planName;
    }

    return 'Unknown';
  }

  String get subscriptionStatus {
    if (enrollmentStatus != null) {
      return enrollmentStatus!.status;
    }

    if (userEnrollment != null) {
      return userEnrollment!.isActive ? 'active' : 'inactive';
    }

    return isEnrolled ? 'enrolled' : 'not_enrolled';
  }

  Course copyWith({
    int? id,
    String? title,
    String? image,
    String? description,
    String? smallDesc,
    int? category,
    String? categoryName,
    String? location,
    String? priceOneMonth,
    String? priceThreeMonths,
    String? priceLifetime,
    bool? isFeatured,
    String? dateUploaded,
    int? enrolledStudents,
    bool? isEnrolled,
    bool? isWishlisted,
    List<CourseObjective>? objectives,
    List<CourseRequirement>? requirements,
    List<CourseCurriculum>? curriculum,
    UserEnrollment? userEnrollment,
    EnrollmentStatus? enrollmentStatus,
  }) {
    return Course(
      id: id ?? this.id,
      title: title ?? this.title,
      image: image ?? this.image,
      description: description ?? this.description,
      smallDesc: smallDesc ?? this.smallDesc,
      category: category ?? this.category,
      categoryName: categoryName ?? this.categoryName,
      location: location ?? this.location,
      priceOneMonth: priceOneMonth ?? this.priceOneMonth,
      priceThreeMonths: priceThreeMonths ?? this.priceThreeMonths,
      priceLifetime: priceLifetime ?? this.priceLifetime,
      isFeatured: isFeatured ?? this.isFeatured,
      dateUploaded: dateUploaded ?? this.dateUploaded,
      enrolledStudents: enrolledStudents ?? this.enrolledStudents,
      isEnrolled: isEnrolled ?? this.isEnrolled,
      isWishlisted: isWishlisted ?? this.isWishlisted,
      objectives: objectives ?? this.objectives,
      requirements: requirements ?? this.requirements,
      curriculum: curriculum ?? this.curriculum,
      userEnrollment: userEnrollment ?? this.userEnrollment,
      enrollmentStatus: enrollmentStatus ?? this.enrollmentStatus,
    );
  }
}

// ✅ UserEnrollment class - same as your original
class UserEnrollment extends Model {
  final int id;
  final String planType;
  final String planName;
  final DateTime? expiryDate;
  final bool isActive;
  final bool isExpired;

  static String storageKey = "user_enrollment";

  UserEnrollment({
    required this.id,
    required this.planType,
    required this.planName,
    this.expiryDate,
    required this.isActive,
    required this.isExpired,
  }) : super(key: storageKey);

  UserEnrollment.fromJson(dynamic data)
      : id = data['id'] ?? 0,
        planType = data['plan_type'] ?? '',
        planName = data['plan_name'] ?? '',
        expiryDate = data['expiry_date'] != null
            ? DateTime.tryParse(data['expiry_date'].toString())
            : null,
        isActive = data['is_active'] == true || data['is_active'] == 'true',
        isExpired = data['is_expired'] == true || data['is_expired'] == 'true',
        super(key: storageKey);

  @override
  toJson() {
    return {
      'id': id,
      'plan_type': planType,
      'plan_name': planName,
      'expiry_date': expiryDate?.toIso8601String(),
      'is_active': isActive,
      'is_expired': isExpired,
    };
  }
}

// ✅ FIXED: EnrollmentStatus class with debug logging
class EnrollmentStatus extends Model {
  final String status;
  final String message;
  final String planType;
  final String planName;
  final DateTime? expiresOn;
  final bool isLifetime;

  static String storageKey = "enrollment_status";

  EnrollmentStatus({
    required this.status,
    required this.message,
    required this.planType,
    required this.planName,
    this.expiresOn,
    required this.isLifetime,
  }) : super(key: storageKey);

  EnrollmentStatus.fromJson(dynamic data)
      : status = data['status'] ?? '',
        message = data['message'] ?? '',
        planType = data['plan_type'] ?? '',
        planName = data['plan_name'] ?? '',
        expiresOn = data['expires_on'] != null
            ? DateTime.tryParse(data['expires_on'].toString())
            : null,
        isLifetime =
            data['is_lifetime'] == true || data['is_lifetime'] == 'true',
        super(key: storageKey);

  @override
  toJson() {
    return {
      'status': status,
      'message': message,
      'plan_type': planType,
      'plan_name': planName,
      'expires_on': expiresOn?.toIso8601String(),
      'is_lifetime': isLifetime,
    };
  }

  // ✅ FIXED: Add debug logging
  bool get isExpired {
    bool expired = status != 'active';
    NyLogger.info(
        '   EnrollmentStatus.isExpired: status="$status" -> expired=$expired');
    return expired;
  }

  bool get isActive {
    bool active = status == 'active';
    NyLogger.info(
        '   EnrollmentStatus.isActive: status="$status" -> active=$active');
    return active;
  }
}

// Other classes remain the same...
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
  final String? duration;

  static String storageKey = "course_curriculum";

  CourseCurriculum({
    required this.id,
    required this.title,
    required this.videoUrl,
    this.order = 0,
    this.duration,
  }) : super(key: storageKey);

  CourseCurriculum.fromJson(dynamic data)
      : id = data['id'] ?? 0,
        title = data['title'] ?? '',
        videoUrl = data['video_url'] ?? '',
        order = data['order'] ?? 0,
        duration = data['duration']?.toString(),
        super(key: storageKey);

  @override
  toJson() {
    return {
      'id': id,
      'title': title,
      'video_url': videoUrl,
      'order': order,
      'duration': duration,
    };
  }
}
