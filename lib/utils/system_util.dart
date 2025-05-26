import 'package:nylo_framework/nylo_framework.dart';

import '../app/models/enrollment.dart';
import '../app/networking/category_api_service.dart';
import '../app/networking/course_api_service.dart';
import '../app/networking/notification_api_service.dart';
import '../app/networking/purchase_api_service.dart';

Future<void> preloadEssentialData() async {
  try {
    // Get services
    CategoryApiService categoryApiService = CategoryApiService();
    CourseApiService courseService = CourseApiService();
    PurchaseApiService subscriptionService = PurchaseApiService();
    NotificationApiService notificationService = NotificationApiService();

    // Load general data
    await categoryApiService.preloadEssentialData();
    await courseService.preloadEssentialData();

    // Check if authenticated to load user-specific data
    bool isAuthenticated = await Auth.isAuthenticated();
    print(isAuthenticated);
    if (isAuthenticated) {
      await subscriptionService.preloadSubscriptionData();
      await notificationService.preloadNotificationsData();
    }
  } catch (e) {
    NyLogger.error('Error preloading essential data: ${e.toString()}');
  }
}

Future<Map<String, String>> getAuthHeaders() async {
  final authToken = await backpackRead('auth_token');
  if (authToken != null) {
    return {
      "Authorization": "Token $authToken",
    };
  }
  return {};
}

DateTime calculateExpiryDate(String planType, DateTime startDate) {
  switch (planType) {
    case Enrollment.PLAN_TYPE_ONE_MONTH:
      return startDate.add(Duration(days: 30));
    case Enrollment.PLAN_TYPE_THREE_MONTHS:
      return startDate.add(Duration(days: 90));
    case Enrollment.PLAN_TYPE_LIFETIME:
      return DateTime(9999, 12, 31); // Far future date for lifetime plans
    default:
      return startDate.add(Duration(days: 30)); // Default to monthly
  }
}
