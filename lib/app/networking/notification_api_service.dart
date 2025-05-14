import 'dart:convert';

import 'package:flutter/material.dart';
import '/config/decoders.dart';
import 'package:nylo_framework/nylo_framework.dart';

class NotificationApiService extends NyApiService {
  NotificationApiService({BuildContext? buildContext})
      : super(buildContext, decoders: modelDecoders);

  @override
  String get baseUrl => getEnv('API_BASE_URL') + "/api";

  /// Get all notifications
  Future<List<dynamic>> getNotifications(
      {bool onlyUnread = false, bool refresh = false}) async {
    // Get auth token
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    // Create a cache key
    final cacheKey = onlyUnread ? 'notifications_unread' : 'notifications_all';

    // Check cache first if not forcing refresh
    if (!refresh) {
      final cached = await storageRead(cacheKey);
      if (cached != null) {
        return cached;
      }
    }

    // Build query parameters
    Map<String, dynamic> queryParams = {};
    if (onlyUnread) {
      queryParams['is_seen'] = 'false';
    }

    return await network(
        request: (request) => request.get(
              "/notifications/",
              queryParameters: queryParams,
            ),
        headers: {
          "Authorization": "Token ${authToken}",
        },
        handleSuccess: (Response response) async {
          // Cache the data
          await storageSave(cacheKey, response.data);

          // Return the data
          return response.data;
        },
        handleFailure: (DioException dioError) {
          throw Exception("Failed to fetch notifications: ${dioError.message}");
        });
  }

  /// Get notification details
  Future<dynamic> getNotificationDetails(int notificationId,
      {bool refresh = false}) async {
    // Get auth token
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    // Create a cache key
    final cacheKey = 'notification_$notificationId';

    // Check cache first if not forcing refresh
    if (!refresh) {
      final cached = await storageRead(cacheKey);
      if (cached != null) {
        return cached;
      }
    }

    return await network(
        request: (request) => request.get("/notifications/$notificationId/"),
        headers: {
          "Authorization": "Token ${authToken}",
        },
        handleSuccess: (Response response) async {
          // Cache the data
          await storageSave(cacheKey, response.data);

          // Return the data
          return response.data;
        },
        handleFailure: (DioException dioError) {
          throw Exception(
              "Failed to fetch notification details: ${dioError.message}");
        });
  }

  /// Mark notification as seen
  Future<bool> markNotificationAsSeen(int notificationId) async {
    // Get auth token
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    return await network(
        request: (request) => request
            .post("/notifications/$notificationId/mark_as_seen/", data: {}),
        headers: {
          "Authorization": "Token ${authToken}",
        },
        handleSuccess: (Response response) async {
          // Invalidate notifications caches
          await storageDelete('notifications_all');
          await storageDelete('notifications_unread');
          await storageDelete('notification_$notificationId');

          return true;
        },
        handleFailure: (DioException dioError) {
          throw Exception(
              "Failed to mark notification as seen: ${dioError.message}");
        });
  }

  /// Mark all notifications as seen
  Future<bool> markAllNotificationsAsSeen() async {
    // Get auth token
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    return await network(
        request: (request) =>
            request.post("/notifications/mark_all_as_seen/", data: {}),
        headers: {
          "Authorization": "Token ${authToken}",
        },
        handleSuccess: (Response response) async {
          // Invalidate notifications caches
          await storageDelete('notifications_all');
          await storageDelete('notifications_unread');

          // Also delete any individual notification caches

          return true;
        },
        handleFailure: (DioException dioError) {
          throw Exception(
              "Failed to mark all notifications as seen: ${dioError.message}");
        });
  }

  /// Delete a notification
  Future<bool> deleteNotification(int notificationId) async {
    // Get auth token
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    return await network(
        request: (request) => request.delete("/notifications/$notificationId/"),
        headers: {
          "Authorization": "Token ${authToken}",
        },
        handleSuccess: (Response response) async {
          // Invalidate notifications caches
          await storageDelete('notifications_all');
          await storageDelete('notifications_unread');
          await storageDelete('notification_$notificationId');

          return true;
        },
        handleFailure: (DioException dioError) {
          throw Exception("Failed to delete notification: ${dioError.message}");
        });
  }

  /// Register device for push notifications
  Future<dynamic> registerDevice({
    required String registrationId,
    required String deviceId,
    bool active = true,
  }) async {
    // Get auth token
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    return await network(
        request: (request) => request.post(
              "/devices/",
              data: {
                "registration_id": registrationId,
                "device_id": deviceId,
                "active": active,
              },
            ),
        headers: {
          "Authorization": "Token ${authToken}",
        },
        handleSuccess: (Response response) async {
          // Store device data
          await storageSave('device_info', response.data);

          return response.data;
        },
        handleFailure: (DioException dioError) {
          throw Exception("Failed to register device: ${dioError.message}");
        });
  }

  /// Update device registration
  Future<dynamic> updateDeviceRegistration({
    required int deviceId,
    required String registrationId,
    bool active = true,
  }) async {
    // Get auth token
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    return await network(
        request: (request) => request.put(
              "/devices/$deviceId/",
              data: {
                "registration_id": registrationId,
                "device_id": deviceId.toString(),
                "active": active,
              },
            ),
        headers: {
          "Authorization": "Token ${authToken}",
        },
        handleSuccess: (Response response) async {
          // Update device data
          await storageSave('device_info', response.data);

          return response.data;
        },
        handleFailure: (DioException dioError) {
          throw Exception(
              "Failed to update device registration: ${dioError.message}");
        });
  }

  /// Unregister device
  Future<bool> unregisterDevice(int deviceId) async {
    // Get auth token
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    return await network(
        request: (request) => request.delete("/devices/$deviceId/"),
        headers: {
          "Authorization": "Token ${authToken}",
        },
        handleSuccess: (Response response) async {
          // Clear device data
          await storageDelete('device_info');

          return true;
        },
        handleFailure: (DioException dioError) {
          throw Exception("Failed to unregister device: ${dioError.message}");
        });
  }

  /// Get unread notification count
  Future<int> getUnreadNotificationCount({bool refresh = false}) async {
    try {
      final notifications =
          await getNotifications(onlyUnread: true, refresh: refresh);
      return notifications.length;
    } catch (e) {
      return 0;
    }
  }

  /// Preload notifications data
  Future<void> preloadNotificationsData() async {
    try {
      // Check if user is authenticated
      final isAuthenticated = await backpackRead('auth_token') != null;

      // If authenticated, preload notifications
      if (isAuthenticated) {
        await Future.wait([
          getNotifications(),
          getNotifications(onlyUnread: true),
        ]);
      }
    } catch (e) {
      // Silently handle errors - this is just preloading
      NyLogger.error('Failed to preload notifications data: ${e.toString()}');
    }
  }
}
