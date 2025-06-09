import 'package:flutter_app/app/models/course.dart';
import 'package:nylo_framework/nylo_framework.dart';

class Enrollment extends Model {
  final int id;
  final SimplerCourse course;
  final DateTime dateEnrolled;
  final String planType;
  final String planName;
  final DateTime? expiryDate;
  final double amountPaid;
  final bool isActive;
  final bool isExpired;
  final int? daysRemaining; // New field - nullable for lifetime plans
  final int totalCurriculum; // New field
  final int totalDuration; // New field in minutes

  static String storageKey = "enrollment";

  // Define constants for plan types
  static const String PLAN_TYPE_ONE_MONTH = 'ONE_MONTH';
  static const String PLAN_TYPE_THREE_MONTHS = 'THREE_MONTHS';
  static const String PLAN_TYPE_LIFETIME = 'LIFETIME';

  Enrollment({
    required this.id,
    required this.course,
    required this.dateEnrolled,
    required this.planType,
    required this.planName,
    this.expiryDate,
    required this.amountPaid,
    this.isActive = true,
    this.isExpired = false,
    this.daysRemaining,
    required this.totalCurriculum,
    required this.totalDuration,
  }) : super(key: storageKey);

  Enrollment.fromJson(dynamic data)
      : id = data['id'] ?? 0,
        course = SimplerCourse.fromJson(data['course'] ?? {}),
        dateEnrolled = _parseDateTime(data['date_enrolled']),
        planType = data['plan_type'] ?? '',
        planName = data['plan_name'] ?? '',
        expiryDate = data['expiry_date'] != null
            ? _parseDateTime(data['expiry_date'])
            : null,
        amountPaid = _parseDouble(data['amount_paid']),
        isActive = _parseBool(data['is_active']),
        isExpired = _parseBool(data['is_expired']),
        daysRemaining = data['days_remaining'], // Can be null for lifetime
        totalCurriculum = data['total_curriculum'] ?? 0,
        totalDuration = data['total_duration'] ?? 0,
        super(key: storageKey);

  static DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    return DateTime.now();
  }

  static double _parseDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  static bool _parseBool(dynamic value) {
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    if (value is int) return value == 1;
    return false;
  }

  @override
  toJson() {
    return {
      'id': id,
      'course': course.toJson(),
      'date_enrolled': dateEnrolled.toIso8601String(),
      'plan_type': planType,
      'plan_name': planName,
      'expiry_date': expiryDate?.toIso8601String(),
      'amount_paid': amountPaid,
      'is_active': isActive,
      'is_expired': isExpired,
      'days_remaining': daysRemaining,
      'total_curriculum': totalCurriculum,
      'total_duration': totalDuration,
    };
  }

  // ✅ Enhanced validation method - now uses API-provided fields
  bool get isValid {
    NyLogger.info(
        '🔍 Checking enrollment validity for course ${course.id} (${course.title}):');
    NyLogger.info('   Plan Type: $planType');
    NyLogger.info('   Is Active: $isActive');
    NyLogger.info('   Is Expired: $isExpired');
    NyLogger.info('   Days Remaining: $daysRemaining');

    // First check if enrollment is active and not expired
    if (!isActive || isExpired) {
      NyLogger.info('   ❌ Enrollment is inactive or expired');
      return false;
    }

    // For lifetime plans
    if (planType == PLAN_TYPE_LIFETIME) {
      NyLogger.info('   ✅ Lifetime plan - valid');
      return true;
    }

    // For time-based plans, use API-provided days_remaining
    if (daysRemaining == null || daysRemaining! <= 0) {
      NyLogger.info('   ❌ No days remaining or expired');
      return false;
    }

    NyLogger.info('   ✅ ${daysRemaining} days remaining - valid');
    return true;
  }

  // Additional helper methods
  bool get isLifetimePlan => planType == PLAN_TYPE_LIFETIME;

  bool get isOneMonthPlan => planType == PLAN_TYPE_ONE_MONTH;

  bool get isThreeMonthPlan => planType == PLAN_TYPE_THREE_MONTHS;

  // Get subscription status as a readable string
  String get subscriptionStatus {
    if (!isActive) return 'Inactive';
    if (isExpired) return 'Expired';
    if (planType == PLAN_TYPE_LIFETIME) return 'Lifetime Active';

    if (daysRemaining == null || daysRemaining! <= 0) return 'Expired';
    if (daysRemaining! <= 7) return 'Expiring Soon (${daysRemaining} days)';

    return 'Active (${daysRemaining} days remaining)';
  }

  // Format total duration as readable string
  String get formattedDuration {
    if (totalDuration <= 0) return 'N/A';

    int hours = totalDuration ~/ 60;
    int minutes = totalDuration % 60;

    if (hours > 0) {
      return minutes > 0 ? '${hours}h ${minutes}m' : '${hours}h';
    } else {
      return '${minutes}m';
    }
  }

  // Get curriculum info as readable string
  String get curriculumInfo {
    return '$totalCurriculum lessons • ${formattedDuration}';
  }
}

class SubscriptionPlan extends Model {
  final int id;
  final String name;
  final String planType;
  final bool isPro;
  final String amount;
  final List<PlanFeature> features;

  static String storageKey = "subscription_plan";

  SubscriptionPlan({
    required this.id,
    required this.name,
    required this.amount,
    required this.planType,
    this.isPro = false,
    this.features = const [],
  }) : super(key: storageKey);

  SubscriptionPlan.fromJson(dynamic data)
      : id = data['id'] ?? 0,
        name = data['name'] ?? '',
        isPro = data['is_pro'] ?? false,
        planType = data['plan_type'],
        amount = data['amount'] ?? '',
        features = (data['features'] ?? [])
            .map<PlanFeature>((feature) => PlanFeature.fromJson(feature))
            .toList(),
        super(key: storageKey);

  @override
  toJson() {
    return {
      'id': id,
      'name': name,
      'is_pro': isPro,
      'plan_type': planType,
      'amount': amount,
      'features': features.map((feature) => feature.toJson()).toList(),
    };
  }
}

class PlanFeature extends Model {
  final int id;
  final String description;

  static String storageKey = "plan_feature";

  PlanFeature({
    required this.id,
    required this.description,
  }) : super(key: storageKey);

  PlanFeature.fromJson(dynamic data)
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

class UserSubscription extends Model {
  final int id;
  final int plan;
  final String planName;
  final String planAmount;
  final String startDate;
  final String endDate;
  final bool isActive;
  final bool isExpired;

  static String storageKey = "user_subscription";

  UserSubscription({
    required this.id,
    required this.plan,
    required this.planName,
    required this.planAmount,
    required this.startDate,
    required this.endDate,
    this.isActive = true,
    this.isExpired = false,
  }) : super(key: storageKey);

  UserSubscription.fromJson(dynamic data)
      : id = data['id'] ?? 0,
        plan = data['plan'] ?? 0,
        planName = data['plan_name'] ?? '',
        planAmount = data['plan_amount'] ?? '',
        startDate = data['start_date'] ?? '',
        endDate = data['end_date'] ?? '',
        isActive = data['is_active'] ?? true,
        isExpired = data['is_expired'] ?? false,
        super(key: storageKey);

  @override
  toJson() {
    return {
      'id': id,
      'plan': plan,
      'plan_name': planName,
      'plan_amount': planAmount,
      'start_date': startDate,
      'end_date': endDate,
      'is_active': isActive,
      'is_expired': isExpired,
    };
  }
}

class EnrollmentDetails extends Model {
  final int id;
  final Course course;
  final DateTime dateEnrolled;
  final String planType;
  final String planName;
  final DateTime? expiryDate;
  final double amountPaid;
  final bool isActive;
  final bool isExpired;

  static String storageKey = "enrollment_details";

  // Define constants for plan types
  static const String PLAN_TYPE_ONE_MONTH = 'ONE_MONTH';
  static const String PLAN_TYPE_THREE_MONTHS = 'THREE_MONTHS';
  static const String PLAN_TYPE_LIFETIME = 'LIFETIME';

  EnrollmentDetails({
    required this.id,
    required this.course,
    required this.dateEnrolled,
    required this.planType,
    required this.planName,
    this.expiryDate,
    required this.amountPaid,
    this.isActive = true,
    this.isExpired = false,
  }) : super(key: storageKey);

  EnrollmentDetails.fromJson(dynamic data)
      : id = data['id'] ?? 0,
        course = Course.fromJson(data['course'] ?? {}),
        dateEnrolled = _parseDateTime(data['date_enrolled']),
        planType = data['plan_type'] ?? '',
        planName = data['plan_name'] ?? '',
        expiryDate = data['expiry_date'] != null
            ? _parseDateTime(data['expiry_date'])
            : null,
        amountPaid = _parseDouble(data['amount_paid']),
        isActive = _parseBool(data['is_active']),
        isExpired = _parseBool(data['is_expired']),
        super(key: storageKey);

  static DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    return DateTime.now();
  }

  static double _parseDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  static bool _parseBool(dynamic value) {
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    if (value is int) return value == 1;
    return false;
  }

  @override
  toJson() {
    return {
      'id': id,
      'course': course.toJson(),
      'date_enrolled': dateEnrolled.toIso8601String(),
      'plan_type': planType,
      'plan_name': planName,
      'expiry_date': expiryDate?.toIso8601String(),
      'amount_paid': amountPaid,
      'is_active': isActive,
      'is_expired': isExpired,
    };
  }

  bool get isValid {
    NyLogger.info(
        '🔍 Checking enrollment validity for course ${course.id} (${course.title}):');
    NyLogger.info('   Plan Type: $planType');
    NyLogger.info('   Is Active: $isActive');
    NyLogger.info('   Is Expired: $isExpired');

    // First check if enrollment is active and not expired
    if (!isActive || isExpired) {
      NyLogger.info('   ❌ Enrollment is inactive or expired');
      return false;
    }

    // For lifetime plans
    if (planType == PLAN_TYPE_LIFETIME) {
      NyLogger.info('   ✅ Lifetime plan - valid');
      return true;
    }

    // For time-based plans, check expiry date
    if (expiryDate == null) {
      NyLogger.info(
          '   ⚠️ No expiry date for non-lifetime plan - assuming invalid');
      return false;
    }

    DateTime now = DateTime.now();
    DateTime expiryDateOnly =
        DateTime(expiryDate!.year, expiryDate!.month, expiryDate!.day);
    DateTime nowDateOnly = DateTime(now.year, now.month, now.day);

    bool isValidDate = nowDateOnly.isBefore(expiryDateOnly) ||
        nowDateOnly.isAtSameMomentAs(expiryDateOnly);

    NyLogger.info('   📅 Current date: ${nowDateOnly.toString()}');
    NyLogger.info('   📅 Expiry date: ${expiryDateOnly.toString()}');
    NyLogger.info('   ✅ Date validation: $isValidDate');

    return isValidDate;
  }

  // Additional helper methods
  bool get isLifetimePlan => planType == PLAN_TYPE_LIFETIME;

  bool get isOneMonthPlan => planType == PLAN_TYPE_ONE_MONTH;

  bool get isThreeMonthPlan => planType == PLAN_TYPE_THREE_MONTHS;

  // Get days remaining for subscription
  int? get daysRemaining {
    if (planType == PLAN_TYPE_LIFETIME) return null; // Lifetime has no expiry
    if (expiryDate == null) return 0;

    DateTime now = DateTime.now();
    if (expiryDate!.isBefore(now)) return 0;

    return expiryDate!.difference(now).inDays;
  }

  // Get subscription status as a readable string
  String get subscriptionStatus {
    if (!isActive) return 'Inactive';
    if (isExpired) return 'Expired';
    if (planType == PLAN_TYPE_LIFETIME) return 'Lifetime Active';

    int? days = daysRemaining;
    if (days == null) return 'Active';
    if (days <= 0) return 'Expired';
    if (days <= 7) return 'Expiring Soon ($days days)';

    return 'Active ($days days remaining)';
  }
}
