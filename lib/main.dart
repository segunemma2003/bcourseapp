import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'bootstrap/boot.dart';

// Top-level function for handling background messages
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  if (message.notification != null) {
    await PushNotification(
      title: message.notification!.title ?? "New notification",
      body: message.notification!.body ?? "",
    ).addSound("default").addImportance(Importance.max).send();
  }
}

/// Main entry point for the application.
void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase before Nylo
  try {
    await Firebase.initializeApp();

    // Set background message handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Request permissions for iOS
    if (Platform.isIOS) {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    }
  } catch (e) {
    print('Error initializing Firebase: $e');
  }

  // Initialize Nylo
  await Nylo.init(
    setup: Boot.nylo,
    setupFinished: Boot.finished,
    showSplashScreen: true,
  );
}
