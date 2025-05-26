import 'package:nylo_framework/nylo_framework.dart';

/// Central cache invalidation manager to coordinate cache clearing across services
/// Call this after major user actions like payments, enrollments, profile updates, etc.
class CacheInvalidationManager {
  /// Invalidate all caches after user login
  static Future<void> onUserLogin() async {
    try {
      // Clear all user-specific caches to ensure fresh data
      await Future.wait([
        // Course-related caches
        cache().clear('enrolled_courses'),
        cache().clear('wishlist'),

        // Notification caches
        cache().clear('notifications_all'),
        cache().clear('notifications_unread'),

        // Purchase/subscription caches
        cache().clear('user_subscriptions'),
        cache().clear('payment_cards'),
        cache().clear('purchase_history'),
      ]);

      NyLogger.info('User login cache invalidation completed');
    } catch (e) {
      NyLogger.error('Error during user login cache invalidation: $e');
    }
  }

  /// Invalidate all caches after user logout
  static Future<void> onUserLogout() async {
    try {
      // Clear all user-specific caches
      await Future.wait([
        // Course-related caches
        cache().clear('enrolled_courses'),
        cache().clear('wishlist'),

        // Notification caches
        cache().clear('notifications_all'),
        cache().clear('notifications_unread'),
        cache().clear('device_info'),

        // Purchase/subscription caches
        cache().clear('user_subscriptions'),
        cache().clear('payment_cards'),
        cache().clear('purchase_history'),

        // Clear any course-specific complete details (these contain enrollment info)
        // Note: You might want to implement a way to track and clear these systematically
      ]);

      NyLogger.info('User logout cache invalidation completed');
    } catch (e) {
      NyLogger.error('Error during user logout cache invalidation: $e');
    }
  }

  /// Invalidate caches after course purchase
  static Future<void> onCoursePurchase(int courseId) async {
    try {
      await Future.wait([
        // Course-related caches
        cache().clear('enrolled_courses'),
        cache().clear('course_details_$courseId'),
        cache().clear('course_complete_details_$courseId'),
        cache().clear('wishlist'), // Course might have been in wishlist

        // Purchase-related caches
        cache().clear('purchase_history'),
        cache()
            .clear('user_subscriptions'), // In case subscription was involved
      ]);

      NyLogger.info(
          'Course purchase cache invalidation completed for course $courseId');
    } catch (e) {
      NyLogger.error('Error during course purchase cache invalidation: $e');
    }
  }

  /// Invalidate caches after course enrollment (free courses)
  static Future<void> onCourseEnrollment(int courseId) async {
    try {
      await Future.wait([
        cache().clear('enrolled_courses'),
        cache().clear('course_details_$courseId'),
        cache().clear('course_complete_details_$courseId'),
      ]);

      NyLogger.info(
          'Course enrollment cache invalidation completed for course $courseId');
    } catch (e) {
      NyLogger.error('Error during course enrollment cache invalidation: $e');
    }
  }

  /// Invalidate caches after subscription purchase/cancellation
  static Future<void> onSubscriptionChange() async {
    try {
      await Future.wait([
        cache().clear('user_subscriptions'),
        cache().clear('purchase_history'),
        cache().clear(
            'enrolled_courses'), // Subscription might affect course access
      ]);

      NyLogger.info('Subscription change cache invalidation completed');
    } catch (e) {
      NyLogger.error('Error during subscription change cache invalidation: $e');
    }
  }

  /// Invalidate caches after payment method changes
  static Future<void> onPaymentMethodChange() async {
    try {
      await cache().clear('payment_cards');

      NyLogger.info('Payment method change cache invalidation completed');
    } catch (e) {
      NyLogger.error('Error during payment method cache invalidation: $e');
    }
  }

  /// Invalidate caches after wishlist changes
  static Future<void> onWishlistChange() async {
    try {
      await cache().clear('wishlist');

      NyLogger.info('Wishlist change cache invalidation completed');
    } catch (e) {
      NyLogger.error('Error during wishlist cache invalidation: $e');
    }
  }

  /// Invalidate caches after notification actions
  static Future<void> onNotificationAction() async {
    try {
      await Future.wait([
        cache().clear('notifications_all'),
        cache().clear('notifications_unread'),
      ]);

      NyLogger.info('Notification action cache invalidation completed');
    } catch (e) {
      NyLogger.error('Error during notification cache invalidation: $e');
    }
  }

  /// Invalidate caches after profile update
  static Future<void> onProfileUpdate() async {
    try {
      // Profile changes might affect enrollment status or other user-specific data
      await Future.wait([
        cache().clear('enrolled_courses'),
        cache().clear('user_subscriptions'),
      ]);

      NyLogger.info('Profile update cache invalidation completed');
    } catch (e) {
      NyLogger.error('Error during profile update cache invalidation: $e');
    }
  }

  /// Force refresh all user-specific data (use sparingly)
  static Future<void> forceRefreshAllUserData() async {
    try {
      await Future.wait([
        // Course-related caches
        cache().clear('enrolled_courses'),
        cache().clear('wishlist'),

        // Notification caches
        cache().clear('notifications_all'),
        cache().clear('notifications_unread'),

        // Purchase/subscription caches
        cache().clear('user_subscriptions'),
        cache().clear('payment_cards'),
        cache().clear('purchase_history'),
      ]);

      NyLogger.info('Force refresh of all user data completed');
    } catch (e) {
      NyLogger.error('Error during force refresh of user data: $e');
    }
  }

  /// Invalidate static data caches (use when admin updates content)
  static Future<void> onStaticDataUpdate() async {
    try {
      await Future.wait([
        // Course data
        cache().clear('featured_courses'),
        cache().clear('top_courses'),
        cache().clear('categories'),
        cache().clear('categories_with_count'),

        // Subscription data
        cache().clear('subscription_plans'),

        // App content
        cache().clear('app_settings'),
        cache().clear('content_page_privacy'),
        cache().clear('content_page_terms'),
      ]);

      NyLogger.info('Static data cache invalidation completed');
    } catch (e) {
      NyLogger.error('Error during static data cache invalidation: $e');
    }
  }

  /// Clean up all expired caches (call periodically)
  static Future<void> cleanupExpiredCaches() async {
    try {
      // Note: Nylo's cache automatically handles expiration, but you might want to
      // implement custom cleanup logic here if needed

      NyLogger.info('Cache cleanup completed');
    } catch (e) {
      NyLogger.error('Error during cache cleanup: $e');
    }
  }

  /// Get cache size estimation for monitoring
  static Future<Map<String, dynamic>> getCacheInfo() async {
    try {
      final cacheKeys = [
        // Course caches
        'featured_courses',
        'top_courses',
        'enrolled_courses',
        'wishlist',
        'categories',

        // Notification caches
        'notifications_all',
        'notifications_unread',

        // Purchase caches
        'user_subscriptions',
        'payment_cards',
        'purchase_history',
        'subscription_plans',

        // Content caches
        'app_settings',
        'content_page_privacy',
        'content_page_terms',
      ];

      Map<String, bool> cacheStatus = {};

      for (String key in cacheKeys) {
        cacheStatus[key] = await cache().has(key);
      }

      return {
        'cached_items': cacheStatus,
        'total_cached': cacheStatus.values.where((v) => v).length,
        'total_possible': cacheKeys.length,
      };
    } catch (e) {
      NyLogger.error('Error getting cache info: $e');
      return {'error': e.toString()};
    }
  }

  /// Invalidate course-specific caches (when course data changes)
  static Future<void> onCourseDataUpdate(int courseId) async {
    try {
      await Future.wait([
        cache().clear('course_details_$courseId'),
        cache().clear('course_complete_details_$courseId'),
        cache().clear('course_curriculum_$courseId'),
        cache().clear('course_objectives_$courseId'),
        cache().clear('course_requirements_$courseId'),

        // Also invalidate course lists that might contain this course
        cache().clear('featured_courses'),
        cache().clear('top_courses'),
        // Note: You might want to be more selective about which course lists to invalidate
      ]);

      NyLogger.info(
          'Course data update cache invalidation completed for course $courseId');
    } catch (e) {
      NyLogger.error('Error during course data update cache invalidation: $e');
    }
  }

  /// Invalidate category-specific caches
  static Future<void> onCategoryDataUpdate(int? categoryId) async {
    try {
      if (categoryId != null) {
        await Future.wait([
          cache().clear('category_details_$categoryId'),
          cache().clear('courses_category_$categoryId'),
        ]);
      }

      // Always invalidate general category caches
      await Future.wait([
        cache().clear('categories'),
        cache().clear('categories_with_count'),
      ]);

      NyLogger.info('Category data update cache invalidation completed');
    } catch (e) {
      NyLogger.error(
          'Error during category data update cache invalidation: $e');
    }
  }

  /// Emergency cache flush (nuclear option - use only in critical situations)
  static Future<void> emergencyFlushAllCaches() async {
    try {
      await cache().flush();
      NyLogger.error('EMERGENCY: All caches have been flushed');
    } catch (e) {
      NyLogger.error('Error during emergency cache flush: $e');
    }
  }
}
