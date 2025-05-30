import 'dart:io';
import 'dart:ui'; // Add this import for PlatformDispatcher
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'bootstrap/boot.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

// Top-level function for handling background messages
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  try {
    if (message.notification != null) {
      await PushNotification(
        title: message.notification!.title ?? "New notification",
        body: message.notification!.body ?? "",
      ).addSound("default").addImportance(Importance.max).send();
    }
  } catch (e, stackTrace) {
    // Log background notification errors
    FirebaseCrashlytics.instance.recordError(e, stackTrace,
        reason: 'Background notification handler failed');
  }
}

/// Main entry point for the application.
void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase before Nylo
  try {
    await Firebase.initializeApp();

    // Enable Crashlytics collection in release mode
    if (kReleaseMode) {
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
    }

    // Set up error handlers (only once!)
    FlutterError.onError = (errorDetails) {
      FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
    };

    // Pass all uncaught asynchronous errors to Crashlytics
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };

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

    print('✅ Firebase initialized successfully');
  } catch (e, stackTrace) {
    print('❌ Error initializing Firebase: $e');

    // Even if Firebase fails, we should still try to start the app
    // but log this critical error if Crashlytics is available
    try {
      FirebaseCrashlytics.instance.recordError(
        e,
        stackTrace,
        reason: 'Firebase initialization failed',
        fatal: true,
      );
    } catch (_) {
      // If Crashlytics isn't available, just print
      print('Stack trace: $stackTrace');
    }
  }

  // Initialize Nylo
  try {
    await Nylo.init(
      setup: Boot.nylo,
      setupFinished: Boot.finished,
      showSplashScreen: true,
    );
  } catch (e, stackTrace) {
    print('❌ Error initializing Nylo: $e');

    // Log Nylo initialization errors
    try {
      FirebaseCrashlytics.instance.recordError(
        e,
        stackTrace,
        reason: 'Nylo initialization failed',
        fatal: true,
      );
    } catch (_) {
      print('Stack trace: $stackTrace');
    }

    // You might want to show an error screen or retry mechanism here
    rethrow; // Re-throw to prevent app from starting in broken state
  }
}
