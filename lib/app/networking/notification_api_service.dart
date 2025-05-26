import 'package:flutter/material.dart';
import '/config/decoders.dart';
import 'package:nylo_framework/nylo_framework.dart';

class NotificationApiService extends NyApiService {
  NotificationApiService({BuildContext? buildContext})
      : super(buildContext, decoders: modelDecoders);

  @override
  String get baseUrl => getEnv('API_BASE_URL') + "/api";

  // Cache duration constants - shorter for notifications as they change frequently
  static const Duration CACHE_NOTIFICATIONS = Duration(minutes: 30);
  static const Duration CACHE_NOTIFICATION_DETAILS = Duration(minutes: 15);

  /// Get all notifications with smart caching
  Future<List<dynamic>> getNotifications(
      {bool onlyUnread = false, bool refresh = false}) async {
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    final cacheKey = onlyUnread ? 'notifications_unread' : 'notifications_all';

    if (refresh) {
      await cache().clear(cacheKey);
    }

    // Build query parameters
    Map<String, dynamic> queryParams = {};
    if (onlyUnread) {
      queryParams['is_seen'] = 'false';
    }

    return await network(
        request: (request) =>
            request.get("/notifications/", queryParameters: queryParams),
        headers: {"Authorization": "Token $authToken"},
        cacheKey: cacheKey,
        cacheDuration: CACHE_NOTIFICATIONS,
        handleSuccess: (Response response) {
          return _parseNotificationsResponse(response.data);
        },
        handleFailure: (DioException dioError) {
          throw Exception("Failed to fetch notifications: ${dioError.message}");
        });
  }

  /// Get notification details with caching
  Future<dynamic> getNotificationDetails(int notificationId,
      {bool refresh = false}) async {
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    final cacheKey = 'notification_$notificationId';

    if (refresh) {
      await cache().clear(cacheKey);
    }

    return await network(
        request: (request) => request.get("/notifications/$notificationId/"),
        headers: {"Authorization": "Token $authToken"},
        cacheKey: cacheKey,
        cacheDuration: CACHE_NOTIFICATION_DETAILS,
        handleSuccess: (Response response) => response.data,
        handleFailure: (DioException dioError) {
          throw Exception(
              "Failed to fetch notification details: ${dioError.message}");
        });
  }

  /// Mark notification as seen (invalidates caches)
  Future<bool> markNotificationAsSeen(int notificationId) async {
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    return await network(
        request: (request) => request
            .post("/notifications/$notificationId/mark_as_seen/", data: {}),
        headers: {"Authorization": "Token $authToken"},
        handleSuccess: (Response response) async {
          // Invalidate notifications caches
          await _invalidateNotificationCaches(notificationId);
          return true;
        },
        handleFailure: (DioException dioError) {
          throw Exception(
              "Failed to mark notification as seen: ${dioError.message}");
        });
  }

  /// Mark all notifications as seen (invalidates all caches)
  Future<bool> markAllNotificationsAsSeen() async {
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    return await network(
        request: (request) =>
            request.post("/notifications/mark_all_as_seen/", data: {}),
        headers: {"Authorization": "Token $authToken"},
        handleSuccess: (Response response) async {
          // Invalidate all notification caches
          await _invalidateAllNotificationCaches();
          return true;
        },
        handleFailure: (DioException dioError) {
          throw Exception(
              "Failed to mark all notifications as seen: ${dioError.message}");
        });
  }

  /// Delete a notification (invalidates caches)
  Future<bool> deleteNotification(int notificationId) async {
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    return await network(
        request: (request) => request.delete("/notifications/$notificationId/"),
        headers: {"Authorization": "Token $authToken"},
        handleSuccess: (Response response) async {
          // Invalidate notification caches
          await _invalidateNotificationCaches(notificationId);
          return true;
        },
        handleFailure: (DioException dioError) {
          throw Exception("Failed to delete notification: ${dioError.message}");
        });
  }

  /// Register device for push notifications (caches device info)
  Future<dynamic> registerDevice({
    required String registrationId,
    required String deviceId,
    bool active = true,
  }) async {
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    return await network(
        request: (request) => request.post("/devices/", data: {
              "registration_id": registrationId,
              "device_id": deviceId,
              "active": active,
            }),
        headers: {"Authorization": "Token $authToken"},
        handleSuccess: (Response response) async {
          // Cache device info for later use
          await cache().saveForever('device_info', () => response.data);
          return response.data;
        },
        handleFailure: (DioException dioError) {
          throw Exception("Failed to register device: ${dioError.message}");
        });
  }

  /// Update device registration (updates cached device info)
  Future<dynamic> updateDeviceRegistration({
    required int deviceId,
    required String registrationId,
    bool active = true,
  }) async {
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    return await network(
        request: (request) => request.put("/devices/$deviceId/", data: {
              "registration_id": registrationId,
              "device_id": deviceId.toString(),
              "active": active,
            }),
        headers: {"Authorization": "Token $authToken"},
        handleSuccess: (Response response) async {
          // Update cached device info
          await cache().saveForever('device_info', () => response.data);
          return response.data;
        },
        handleFailure: (DioException dioError) {
          throw Exception(
              "Failed to update device registration: ${dioError.message}");
        });
  }

  /// Unregister device (clears cached device info)
  Future<bool> unregisterDevice(int deviceId) async {
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    return await network(
        request: (request) => request.delete("/devices/$deviceId/"),
        headers: {"Authorization": "Token $authToken"},
        handleSuccess: (Response response) async {
          // Clear cached device info
          await cache().clear('device_info');
          return true;
        },
        handleFailure: (DioException dioError) {
          throw Exception("Failed to unregister device: ${dioError.message}");
        });
  }

  /// Get unread notification count (uses cached data if available)
  Future<int> getUnreadNotificationCount({bool refresh = false}) async {
    try {
      final notifications =
          await getNotifications(onlyUnread: true, refresh: refresh);
      return notifications.length;
    } catch (e) {
      return 0;
    }
  }

  /// Get cached device info
  Future<dynamic> getCachedDeviceInfo() async {
    return await cache().get('device_info');
  }

  /// Check if notifications are cached
  Future<bool> areNotificationsCached({bool onlyUnread = false}) async {
    final cacheKey = onlyUnread ? 'notifications_unread' : 'notifications_all';
    return await cache().has(cacheKey);
  }

  /// Get notification badge count (optimized for frequent calls)
  Future<int> getNotificationBadgeCount() async {
    try {
      // Try to get from cache first (very fast)
      final cachedUnread = await cache().get('notifications_unread');
      if (cachedUnread != null && cachedUnread is List) {
        return cachedUnread.length;
      }

      // If not cached, fetch with minimal network call
      return await getUnreadNotificationCount();
    } catch (e) {
      return 0;
    }
  }

  /// Preload notifications data
  Future<void> preloadNotificationsData() async {
    try {
      final isAuthenticated = await backpackRead('auth_token') != null;

      if (isAuthenticated) {
        await Future.wait([
          getNotifications().catchError((e) {
            NyLogger.error('Failed to preload all notifications: $e');
            return <dynamic>[];
          }),
          getNotifications(onlyUnread: true).catchError((e) {
            NyLogger.error('Failed to preload unread notifications: $e');
            return <dynamic>[];
          }),
        ]);

        NyLogger.info('Notifications data preloading completed');
      }
    } catch (e) {
      NyLogger.error('Failed to preload notifications data: ${e.toString()}');
    }
  }

  /// Force refresh all notification data
  Future<void> refreshAllNotifications() async {
    try {
      await Future.wait([
        getNotifications(refresh: true),
        getNotifications(onlyUnread: true, refresh: true),
      ]);
      NyLogger.info('All notifications refreshed');
    } catch (e) {
      NyLogger.error('Failed to refresh notifications: $e');
    }
  }

  // Helper methods

  /// Parse notifications response
  List<dynamic> _parseNotificationsResponse(dynamic responseData) {
    try {
      if (responseData is List) {
        return responseData;
      } else if (responseData is Map) {
        // Check common keys for list data
        if (responseData.containsKey('data') && responseData['data'] is List) {
          return responseData['data'];
        } else if (responseData.containsKey('notifications') &&
            responseData['notifications'] is List) {
          return responseData['notifications'];
        } else if (responseData.containsKey('results') &&
            responseData['results'] is List) {
          return responseData['results'];
        }
        return [responseData];
      }
      return responseData != null ? [responseData] : [];
    } catch (e) {
      NyLogger.error('Error parsing notifications response: $e');
      return [];
    }
  }

  /// Invalidate notification caches for specific notification
  Future<void> _invalidateNotificationCaches(int notificationId) async {
    await Future.wait([
      cache().clear('notifications_all'),
      cache().clear('notifications_unread'),
      cache().clear('notification_$notificationId'),
    ]);
  }

  /// Invalidate all notification caches
  Future<void> _invalidateAllNotificationCaches() async {
    await Future.wait([
      cache().clear('notifications_all'),
      cache().clear('notifications_unread'),
    ]);
  }
}
