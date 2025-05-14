import 'package:nylo_framework/nylo_framework.dart';

class Enrollment extends Model {
  final int id;
  final int course;
  final String dateEnrolled;

  static String storageKey = "enrollment";

  Enrollment({
    required this.id,
    required this.course,
    required this.dateEnrolled,
  }) : super(key: storageKey);

  Enrollment.fromJson(dynamic data)
      : id = data['id'] ?? 0,
        course = data['course'] ?? 0,
        dateEnrolled = data['date_enrolled'] ?? '',
        super(key: storageKey);

  @override
  toJson() {
    return {
      'id': id,
      'course': course,
      'date_enrolled': dateEnrolled,
    };
  }
}

class SubscriptionPlan extends Model {
  final int id;
  final String name;
  final bool isPro;
  final String amount;
  final List<PlanFeature> features;

  static String storageKey = "subscription_plan";

  SubscriptionPlan({
    required this.id,
    required this.name,
    required this.amount,
    this.isPro = false,
    this.features = const [],
  }) : super(key: storageKey);

  SubscriptionPlan.fromJson(dynamic data)
      : id = data['id'] ?? 0,
        name = data['name'] ?? '',
        isPro = data['is_pro'] ?? false,
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
