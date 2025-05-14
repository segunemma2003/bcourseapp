import 'package:flutter_app/app/networking/category_api_service.dart';
import 'package:flutter_app/app/networking/purchase_api_service.dart';
import 'package:nylo_framework/nylo_framework.dart';

import '../networking/course_api_service.dart';
import '../networking/notification_api_service.dart';

class ApiServiceProvider implements NyProvider {
  @override
  boot(Nylo nylo) async {
    // boot your provider
    // ...

    return nylo;
  }

  @override
  afterBoot(Nylo nylo) async {
    // Called after Nylo has finished booting
    // ...
    _preloadEssentialData();
  }

  Future<void> _preloadEssentialData() async {
    try {
      // Get services
      CategoryApiService categoryApiService = CategoryApiService();
      CourseApiService courseService = CourseApiService();
      PurchaseApiService subscriptionService = PurchaseApiService();
      NotificationApiService notificationService = NotificationApiService();

      // Load general data
      await categoryApiService.preloadEssentialData();
      // await courseService.preloadEssentialData();

      // Check if authenticated to load user-specific data
      final isAuthenticated = await backpackRead('auth_token') != null;
      if (isAuthenticated) {
        await subscriptionService.preloadSubscriptionData();
        await notificationService.preloadNotificationsData();
      }
    } catch (e) {
      NyLogger.error('Error preloading essential data: ${e.toString()}');
    }
  }
}
