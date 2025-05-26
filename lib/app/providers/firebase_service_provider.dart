import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_app/app/networking/user_api_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:nylo_framework/nylo_framework.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  NyLogger.info("Handling a background message: ${message.messageId}");

  if (message.notification != null) {
    await PushNotification(
      title: message.notification!.title ?? "New notification",
      body: message.notification!.body ?? "",
    ).addSound("default").addImportance(Importance.max).send();
  }
}

class FirebaseServiceProvider implements NyProvider {
  static final FlutterLocalNotificationsPlugin
      _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'high_importance_channel', // id
    'High Importance Notifications', // title
    description:
        'This channel is used for important notifications.', // description
    importance: Importance.high,
  );

  @override
  boot(Nylo nylo) async {
    try {
      await _initializeFirebase();

      await _setupFirebaseMessaging();
    } catch (e) {
      NyLogger.error('Error setting up Firebase: $e');
    }

    return nylo;
  }

  Future<void> _initializeFirebase() async {
    try {
      // Initialize Firebase with the configuration files you downloaded
      await Firebase.initializeApp();
      NyLogger.info('Firebase initialized successfully');
    } catch (e) {
      NyLogger.error('Failed to initialize Firebase: $e');
      rethrow;
    }
  }

  Future<void> _setupFirebaseMessaging() async {
    try {
      // Set the background message handler
      FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler);

      // Get FCM token and store it for later use
      String? token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        NyLogger.info('FCM Token: $token');
        await backpackSave('fcm_token', token);
        UserApiService _userApiService = UserApiService();
        // Register device with backend if user is logged in
        if (await Auth.isAuthenticated()) {
          await _userApiService.registerDeviceWithBackend(token);
        }
      }

      // Set up token refresh listener
      FirebaseMessaging.instance.onTokenRefresh.listen((String newToken) async {
        NyLogger.info('FCM Token refreshed: $newToken');
        await backpackSave('fcm_token', newToken);
        UserApiService _userApiService = UserApiService();

        // Update token on server if user is logged in
        if (await Auth.isAuthenticated()) {
          await _userApiService.registerDeviceWithBackend(newToken);
        }
      });

      // Handle initial message (app was terminated)
      FirebaseMessaging.instance
          .getInitialMessage()
          .then((RemoteMessage? message) {
        if (message != null) {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            _handleMessage(message);
          });
        }
      });

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        NyLogger.info('Got a message in the foreground!');
        NyLogger.info('Message data: ${message.data}');

        if (message.notification != null) {
          NyLogger.info(
              'Message also contained a notification: ${message.notification!.title}');

          _showLocalNotification(message);
        }
      });

      // Handle background messages when app is opened
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        NyLogger.info('A new onMessageOpenedApp event was published!');
        _handleMessage(message);
      });

      // Request permission for iOS and Android 13+
      await _requestNotificationPermissions();

      NyLogger.info('Firebase Messaging setup completed');
    } catch (e) {
      NyLogger.error('Failed to setup Firebase Messaging: $e');
      rethrow;
    }
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    RemoteNotification? notification = message.notification;

    try {
      if (notification != null) {
        // Use Nylo's PushNotification system which is better integrated
        await PushNotification(
          title: notification.title ?? "New notification",
          body: notification.body ?? "",
        )
            .addPayload(jsonEncode(message.data))
            .addId(_generateNotificationId(message))
            .addSound(message.data['sound'] ?? "default")
            .addImportance(Importance.max)
            .addChannelId(_channel.id)
            .addChannelName(_channel.name)
            .addChannelDescription(_channel.description!)
            .send();
      }
    } catch (e) {
      NyLogger.error('Error showing notification: $e');
    }
  }

  // Request permissions for notifications
  Future<void> _requestNotificationPermissions() async {
    try {
      // Use Nylo's built-in permission request
      final settings = await PushNotification.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
          critical: false,
          vibrate: true);

      // Also request specific Firebase permissions for iOS
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      NyLogger.info('Notification permissions requested');
    } catch (e) {
      NyLogger.error('Error requesting notification permissions: $e');
    }
  }

  // Handle incoming message and navigate if needed
  void _handleMessage(RemoteMessage message) {
    try {
      // Extract navigation info from the message if available
      final data = message.data;
      _handleNotificationPayload(data);
    } catch (e) {
      NyLogger.error('Error handling FCM message: $e');
    }
  }

  // Handle notification payload navigation
  void _handleNotificationPayload(Map<String, dynamic> data) {
    try {
      // Route navigation
      if (data.containsKey('route')) {
        String routeName = data['route'];
        routeTo(routeName);
        return;
      }

      // Action type handling
      if (data.containsKey('action_type')) {
        String actionType = data['action_type'];
        switch (actionType) {
          case 'open_profile':
            if (data.containsKey('user_id')) {
              // Navigate to user profile
              // routeTo(ProfilePage.path, data: {'id': data['user_id']});
            }
            break;

          case 'open_chat':
            if (data.containsKey('chat_id')) {
              // Navigate to chat
              // routeTo(ChatPage.path, data: {'id': data['chat_id']});
            }
            break;
        }
      }

      // Notification type handling
      if (data.containsKey('notification_type')) {
        String notificationType = data['notification_type'];
        switch (notificationType) {
          case 'message':
            if (data.containsKey('conversation_id')) {
              // Navigate to conversation
              // routeTo(ChatPage.path, data: {'id': data['conversation_id']});
            }
            break;

          case 'announcement':
            if (data.containsKey('announcement_id')) {
              // Navigate to announcement
              // routeTo(AnnouncementPage.path, data: {'id': data['announcement_id']});
            }
            break;
        }
      }
    } catch (e) {
      NyLogger.error('Error handling notification payload: $e');
    }
  }

  // Register device with your backend

  // Get a unique device identifier

  // Generate a consistent notification ID from the message
  int _generateNotificationId(RemoteMessage message) {
    // First check if the data contains a specific notification ID
    if (message.data.containsKey('notification_id')) {
      try {
        return int.parse(message.data['notification_id']);
      } catch (e) {
        // If parsing fails, use the default approach
      }
    }

    // Use messageId as the base for the notification ID
    return message.messageId?.hashCode ??
        DateTime.now().millisecondsSinceEpoch.remainder(100000);
  }

  // Helper method to subscribe to FCM topics
  static Future<void> subscribeToTopic(String topic) async {
    try {
      await FirebaseMessaging.instance.subscribeToTopic(topic);
      NyLogger.info('Subscribed to FCM topic: $topic');
    } catch (e) {
      NyLogger.error('Error subscribing to topic $topic: $e');
    }
  }

  // Helper method to unsubscribe from FCM topics
  static Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
      NyLogger.info('Unsubscribed from FCM topic: $topic');
    } catch (e) {
      NyLogger.error('Error unsubscribing from topic $topic: $e');
    }
  }

  // Helper method to subscribe a user to their user-specific topic
  static Future<void> subscribeToUserTopics() async {
    try {
      if (await Auth.isAuthenticated()) {
        var userData = await Auth.data();

        if (userData != null && userData['id'] != null) {
          // Subscribe to user-specific topic
          String userId = userData['id'].toString();
          await subscribeToTopic('user_$userId');

          // Subscribe to general topic
          await subscribeToTopic('general');
        }
      }
    } catch (e) {
      NyLogger.error('Error subscribing to user topics: $e');
    }
  }

  // Helper method to unsubscribe from all topics when logging out
  static Future<void> unsubscribeFromAllTopics() async {
    try {
      var userData = await Auth.data();

      // Unsubscribe from general topic
      await unsubscribeFromTopic('general');

      // Unsubscribe from user-specific topic
      if (userData != null && userData['id'] != null) {
        String userId = userData['id'].toString();
        await unsubscribeFromTopic('user_$userId');
      }
    } catch (e) {
      NyLogger.error('Error unsubscribing from topics: $e');
    }
  }

  @override
  afterBoot(Nylo nylo) async {
    // Subscribe to topics if user is already logged in
    if (await Auth.isAuthenticated()) {
      await subscribeToUserTopics();
    }
  }
}
