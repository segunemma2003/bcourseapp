import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:nylo_framework/nylo_framework.dart';

import '../services/video_service.dart';

/// Central cache invalidation manager to coordinate cache clearing across services
/// Call this after major user actions like payments, enrollments, profile updates, etc.
class CacheInvalidationManager {
  /// ✅ FIXED: Invalidate all caches after user login
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

      // ✅ IMPORTANT: Handle user login for VideoService
      await VideoService().handleUserLogin();

      NyLogger.info('User login cache invalidation completed');
    } catch (e, stackTrace) {
      NyLogger.error('Error during user login cache invalidation: $e');

      // 🔥 ADD: Report to Crashlytics
      try {
        FirebaseCrashlytics.instance.recordError(
          Exception('User login cache invalidation failed: $e'),
          stackTrace,
          fatal: false,
        );
      } catch (_) {}
    }
  }

  /// ✅ FIXED: Invalidate all caches after user logout
  static Future<void> onUserLogout() async {
    try {
      // ✅ IMPORTANT: Handle VideoService logout FIRST (to save state)
      await VideoService().handleUserLogout();

      // Then clear all user-specific caches
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
    } catch (e, stackTrace) {
      NyLogger.error('Error during user logout cache invalidation: $e');

      // 🔥 ADD: Report to Crashlytics
      try {
        FirebaseCrashlytics.instance.recordError(
          Exception('User logout cache invalidation failed: $e'),
          stackTrace,
          fatal: false,
        );
      } catch (_) {}
    }
  }

  /// ✅ FIXED: Invalidate caches after course purchase
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

      // ✅ FIXED: Refresh user login state to get updated enrollment data
      await VideoService().handleUserLogin();

      NyLogger.info(
          'Course purchase cache invalidation completed for course $courseId');
    } catch (e, stackTrace) {
      NyLogger.error('Error during course purchase cache invalidation: $e');

      // 🔥 ADD: Report to Crashlytics
      try {
        FirebaseCrashlytics.instance.recordError(
          Exception('Course purchase cache invalidation failed: $e'),
          stackTrace,
          fatal: false,
        );
        FirebaseCrashlytics.instance.setCustomKey('course_id', courseId);
      } catch (_) {}
    }
  }

  /// ✅ FIXED: Invalidate caches after course enrollment (free courses)
  static Future<void> onCourseEnrollment(int courseId) async {
    try {
      await Future.wait([
        cache().clear('enrolled_courses'),
        cache().clear('course_details_$courseId'),
        cache().clear('course_complete_details_$courseId'),
      ]);

      // ✅ ADD: Refresh VideoService to recognize new enrollment
      await VideoService().handleUserLogin();

      NyLogger.info(
          'Course enrollment cache invalidation completed for course $courseId');
    } catch (e, stackTrace) {
      NyLogger.error('Error during course enrollment cache invalidation: $e');

      // 🔥 ADD: Report to Crashlytics
      try {
        FirebaseCrashlytics.instance.recordError(
          Exception('Course enrollment cache invalidation failed: $e'),
          stackTrace,
          fatal: false,
        );
        FirebaseCrashlytics.instance.setCustomKey('course_id', courseId);
      } catch (_) {}
    }
  }

  /// ✅ FIXED: Invalidate caches after subscription purchase/cancellation
  static Future<void> onSubscriptionChange() async {
    try {
      await Future.wait([
        cache().clear('user_subscriptions'),
        cache().clear('purchase_history'),
        cache().clear(
            'enrolled_courses'), // Subscription might affect course access
      ]);

      // ✅ ADD: Refresh VideoService to recognize subscription changes
      await VideoService().handleUserLogin();

      NyLogger.info('Subscription change cache invalidation completed');
    } catch (e, stackTrace) {
      NyLogger.error('Error during subscription change cache invalidation: $e');

      // 🔥 ADD: Report to Crashlytics
      try {
        FirebaseCrashlytics.instance.recordError(
          Exception('Subscription change cache invalidation failed: $e'),
          stackTrace,
          fatal: false,
        );
      } catch (_) {}
    }
  }

  /// 🆕 BONUS: Invalidate caches after subscription renewal
  static Future<void> onSubscriptionRenewal(int courseId) async {
    try {
      await Future.wait([
        // Course-related caches
        cache().clear('enrolled_courses'),
        cache().clear('course_details_$courseId'),
        cache().clear('course_complete_details_$courseId'),

        // Subscription-related caches
        cache().clear('user_subscriptions'),
        cache().clear('purchase_history'),
      ]);

      // Refresh user login state to get updated subscription info
      await VideoService().handleUserLogin();

      NyLogger.info(
          'Subscription renewal cache invalidation completed for course $courseId');
    } catch (e, stackTrace) {
      NyLogger.error(
          'Error during subscription renewal cache invalidation: $e');

      try {
        FirebaseCrashlytics.instance.recordError(
          Exception('Subscription renewal cache invalidation failed: $e'),
          stackTrace,
          fatal: false,
        );
        FirebaseCrashlytics.instance.setCustomKey('course_id', courseId);
      } catch (_) {}
    }
  }

  /// Invalidate caches after payment method changes
  static Future<void> onPaymentMethodChange() async {
    try {
      await cache().clear('payment_cards');

      NyLogger.info('Payment method change cache invalidation completed');
    } catch (e, stackTrace) {
      NyLogger.error('Error during payment method cache invalidation: $e');

      // 🔥 ADD: Report to Crashlytics
      try {
        FirebaseCrashlytics.instance.recordError(
          Exception('Payment method cache invalidation failed: $e'),
          stackTrace,
          fatal: false,
        );
      } catch (_) {}
    }
  }

  /// Invalidate caches after wishlist changes
  static Future<void> onWishlistChange() async {
    try {
      await cache().clear('wishlist');

      NyLogger.info('Wishlist change cache invalidation completed');
    } catch (e, stackTrace) {
      NyLogger.error('Error during wishlist cache invalidation: $e');

      // 🔥 ADD: Report to Crashlytics
      try {
        FirebaseCrashlytics.instance.recordError(
          Exception('Wishlist cache invalidation failed: $e'),
          stackTrace,
          fatal: false,
        );
      } catch (_) {}
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
    } catch (e, stackTrace) {
      NyLogger.error('Error during notification cache invalidation: $e');

      // 🔥 ADD: Report to Crashlytics
      try {
        FirebaseCrashlytics.instance.recordError(
          Exception('Notification cache invalidation failed: $e'),
          stackTrace,
          fatal: false,
        );
      } catch (_) {}
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
    } catch (e, stackTrace) {
      NyLogger.error('Error during profile update cache invalidation: $e');

      // 🔥 ADD: Report to Crashlytics
      try {
        FirebaseCrashlytics.instance.recordError(
          Exception('Profile update cache invalidation failed: $e'),
          stackTrace,
          fatal: false,
        );
      } catch (_) {}
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

      // ✅ ADD: Refresh VideoService after force refresh
      await VideoService().handleUserLogin();

      NyLogger.info('Force refresh of all user data completed');
    } catch (e, stackTrace) {
      NyLogger.error('Error during force refresh of user data: $e');

      // 🔥 ADD: Report to Crashlytics
      try {
        FirebaseCrashlytics.instance.recordError(
          Exception('Force refresh user data failed: $e'),
          stackTrace,
          fatal: false,
        );
      } catch (_) {}
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
    } catch (e, stackTrace) {
      NyLogger.error('Error during static data cache invalidation: $e');

      // 🔥 ADD: Report to Crashlytics
      try {
        FirebaseCrashlytics.instance.recordError(
          Exception('Static data cache invalidation failed: $e'),
          stackTrace,
          fatal: false,
        );
      } catch (_) {}
    }
  }

  /// Clean up all expired caches (call periodically)
  static Future<void> cleanupExpiredCaches() async {
    try {
      // Note: Nylo's cache automatically handles expiration, but you might want to
      // implement custom cleanup logic here if needed

      NyLogger.info('Cache cleanup completed');
    } catch (e, stackTrace) {
      NyLogger.error('Error during cache cleanup: $e');

      // 🔥 ADD: Report to Crashlytics
      try {
        FirebaseCrashlytics.instance.recordError(
          Exception('Cache cleanup failed: $e'),
          stackTrace,
          fatal: false,
        );
      } catch (_) {}
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
    } catch (e, stackTrace) {
      NyLogger.error('Error getting cache info: $e');

      // 🔥 ADD: Report to Crashlytics
      try {
        FirebaseCrashlytics.instance.recordError(
          Exception('Get cache info failed: $e'),
          stackTrace,
          fatal: false,
        );
      } catch (_) {}

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
    } catch (e, stackTrace) {
      NyLogger.error('Error during course data update cache invalidation: $e');

      // 🔥 ADD: Report to Crashlytics
      try {
        FirebaseCrashlytics.instance.recordError(
          Exception('Course data update cache invalidation failed: $e'),
          stackTrace,
          fatal: false,
        );
        FirebaseCrashlytics.instance.setCustomKey('course_id', courseId);
      } catch (_) {}
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
    } catch (e, stackTrace) {
      NyLogger.error(
          'Error during category data update cache invalidation: $e');

      // 🔥 ADD: Report to Crashlytics
      try {
        FirebaseCrashlytics.instance.recordError(
          Exception('Category data update cache invalidation failed: $e'),
          stackTrace,
          fatal: false,
        );
        if (categoryId != null) {
          FirebaseCrashlytics.instance.setCustomKey('category_id', categoryId);
        }
      } catch (_) {}
    }
  }

  /// Emergency cache flush (nuclear option - use only in critical situations)
  static Future<void> emergencyFlushAllCaches() async {
    try {
      // ✅ IMPORTANT: Handle VideoService logout first to save state
      await VideoService().handleUserLogout();

      // Then flush all caches
      await cache().flush();

      NyLogger.error('EMERGENCY: All caches have been flushed');

      // 🔥 ADD: Report emergency action to Crashlytics
      try {
        FirebaseCrashlytics.instance.recordError(
          Exception('Emergency cache flush executed'),
          StackTrace.current,
          fatal: false,
        );
      } catch (_) {}
    } catch (e, stackTrace) {
      NyLogger.error('Error during emergency cache flush: $e');

      // 🔥 ADD: Report to Crashlytics
      try {
        FirebaseCrashlytics.instance.recordError(
          Exception('Emergency cache flush failed: $e'),
          stackTrace,
          fatal: true, // This is critical
        );
      } catch (_) {}
    }
  }
}
