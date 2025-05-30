import 'package:flutter_app/app/networking/category_api_service.dart';
import 'package:flutter_app/app/networking/purchase_api_service.dart';
import 'package:flutter_app/app/networking/user_api_service.dart';
import 'package:nylo_framework/nylo_framework.dart';

import '../networking/course_api_service.dart';
import '../networking/notification_api_service.dart';
import '../networking/token_helper.dart';
// import '../helpers/token_sync_helper.dart'; // Add this import

class ApiServiceProvider implements NyProvider {
  @override
  boot(Nylo nylo) async {
    // Attempt to recover authentication state first
    await _recoverAuthenticationState();

    return nylo;
  }

  @override
  afterBoot(Nylo nylo) async {
    // Called after Nylo has finished booting
    await _preloadEssentialData();
  }

  Future<void> _recoverAuthenticationState() async {
    try {
      NyLogger.info('=== AUTH STATE RECOVERY ===');

      final isAuthenticated = await Auth.isAuthenticated();
      final authToken =
          await TokenSyncHelper.readAuthToken(); // Use sync helper
      final userData = await storageRead("user");

      NyLogger.info('Boot - Auth.isAuthenticated(): $isAuthenticated');
      NyLogger.info('Boot - Auth token exists: ${authToken != null}');
      NyLogger.info('Boot - User data exists: ${userData != null}');

      // Case 1: Everything is consistent
      if (isAuthenticated && authToken != null && userData != null) {
        NyLogger.info('Authentication state is consistent');
        return;
      }

      // Case 2: We have user data but not authenticated - re-authenticate
      if (!isAuthenticated && userData != null) {
        NyLogger.info('Re-authenticating user with stored data');
        try {
          await Auth.authenticate(data: userData);

          // Check if authentication worked
          bool nowAuthenticated = await Auth.isAuthenticated();
          if (nowAuthenticated) {
            NyLogger.info('Re-authentication successful');
          } else {
            NyLogger.error('Re-authentication failed');
          }
        } catch (e) {
          NyLogger.error('Re-authentication error: $e');
          // Clear corrupted data
          await storageDelete("user");
          await TokenSyncHelper.clearAuthToken();
        }
        return;
      }

      // Case 3: User is authenticated but missing token (shouldn't happen normally)
      if (isAuthenticated && authToken == null) {
        NyLogger.error('User authenticated but no token - this is unusual');
        // Let the route guard handle this inconsistent state
        return;
      }

      // Case 4: Clean state - no authentication data
      if (!isAuthenticated && authToken == null && userData == null) {
        NyLogger.info('Clean state - no authentication data found');
        return;
      }

      // Case 5: Any other inconsistent state
      NyLogger.error('Inconsistent authentication state detected');
      NyLogger.info(
          'State: auth=$isAuthenticated, token=${authToken != null}, userData=${userData != null}');
    } catch (e) {
      NyLogger.error('Failed to recover authentication state: $e');
      // Don't clear auth state on boot errors during development
    }
  }

  Future<void> _preloadEssentialData() async {
    try {
      // Get services
      CategoryApiService categoryApiService = CategoryApiService();
      CourseApiService courseService = CourseApiService();
      PurchaseApiService subscriptionService = PurchaseApiService();
      NotificationApiService notificationService = NotificationApiService();

      // Load general data (doesn't require authentication)
      await categoryApiService.preloadEssentialData();

      // Check if authenticated to load user-specific data
      final isAuthenticated = await Auth.isAuthenticated();
      final authToken =
          await TokenSyncHelper.readAuthToken(); // Use sync helper

      // Only load user-specific data if we have both auth states
      if (isAuthenticated && authToken != null) {
        NyLogger.info(
            'Loading user-specific data - user is properly authenticated');
        await subscriptionService.preloadSubscriptionData();
        await notificationService.preloadNotificationsData();
      } else if (isAuthenticated && authToken == null) {
        NyLogger.error(
            'User appears authenticated but no token - skipping user-specific data preload');
      } else {
        NyLogger.info(
            'User not authenticated - skipping user-specific data preload');
      }
    } catch (e) {
      NyLogger.error('Error preloading essential data: ${e.toString()}');
    }
  }
}
