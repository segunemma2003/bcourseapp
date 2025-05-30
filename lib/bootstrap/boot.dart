import 'package:flutter/material.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import '../app/services/video_service.dart';
import '/resources/widgets/splash_screen.dart';
import '/bootstrap/app.dart';
import '/config/providers.dart';
import 'package:nylo_framework/nylo_framework.dart';

/* Boot
|--------------------------------------------------------------------------
| The boot class is used to initialize your application.
| Providers are booted in the order they are defined.
|--------------------------------------------------------------------------
*/

class Boot {
  /// This method is called to initialize Nylo.
  static Future<Nylo> nylo() async {
    WidgetsFlutterBinding.ensureInitialized();

    try {
      // Set up Crashlytics context early
      await _setCrashlyticsContext();

      if (getEnv('SHOW_SPLASH_SCREEN', defaultValue: false)) {
        runApp(SplashScreen.app());
      }

      await _setup();

      final nyloApp = await bootApplication(providers);

      // Log successful boot
      FirebaseCrashlytics.instance.log('Nylo application booted successfully');

      return nyloApp;
    } catch (error, stackTrace) {
      // Log boot errors
      try {
        await FirebaseCrashlytics.instance.recordError(
          error,
          stackTrace,
          reason: 'Failed to boot Nylo application',
          fatal: true,
        );
      } catch (_) {
        print('Failed to log boot error to Crashlytics: $error');
      }

      print('❌ Boot error: $error');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// This method is called after Nylo is initialized.
  static Future<void> finished(Nylo nylo) async {
    try {
      // Boot finished providers
      await bootFinished(nylo, providers);

      // Initialize video service with error handling
      await _initializeVideoService();

      // Log successful initialization
      FirebaseCrashlytics.instance
          .log('App initialization completed successfully');

      runApp(Main(nylo));
    } catch (error, stackTrace) {
      // Log initialization errors
      try {
        await FirebaseCrashlytics.instance.recordError(
          error,
          stackTrace,
          reason: 'Failed to complete app initialization',
          fatal: true,
        );
      } catch (_) {
        print('Failed to log initialization error to Crashlytics: $error');
      }

      print('❌ Initialization error: $error');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Set up Crashlytics context with app information
  static Future<void> _setCrashlyticsContext() async {
    try {
      // Set custom keys for better crash context
      await FirebaseCrashlytics.instance.setCustomKey(
          'app_version', getEnv('APP_VERSION', defaultValue: '1.0.0'));
      await FirebaseCrashlytics.instance.setCustomKey(
          'app_name', getEnv('APP_NAME', defaultValue: 'Unknown'));
      await FirebaseCrashlytics.instance
          .setCustomKey('platform', Platform.operatingSystem);
      await FirebaseCrashlytics.instance.setCustomKey(
          'environment', getEnv('APP_ENV', defaultValue: 'production'));
      await FirebaseCrashlytics.instance
          .setCustomKey('debug_mode', kDebugMode.toString());

      if (kDebugMode) {
        print('✅ Crashlytics context set successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Failed to set Crashlytics context: $e');
      }
    }
  }

  /// Initialize video service with proper error handling
  static Future<void> _initializeVideoService() async {
    try {
      FirebaseCrashlytics.instance.log('Initializing video service');
      await VideoService().initialize();
      FirebaseCrashlytics.instance
          .log('Video service initialized successfully');

      if (kDebugMode) {
        print('✅ Video service initialized successfully');
      }
    } catch (error, stackTrace) {
      // Log video service initialization errors
      await FirebaseCrashlytics.instance.recordError(
        error,
        stackTrace,
        reason: 'Video service initialization failed',
        fatal: false, // Non-fatal since app can continue without video service
      );

      if (kDebugMode) {
        print('⚠️ Video service initialization failed: $error');
      }

      // Don't rethrow - app can continue without video service
    }
  }
}

/* Setup
|--------------------------------------------------------------------------
| You can use _setup to initialize classes, variables, etc.
| It's run before your app providers are booted.
|--------------------------------------------------------------------------
*/

_setup() async {
  try {
    FirebaseCrashlytics.instance.log('Starting app setup');

    /// Example: Initializing StorageConfig
    // StorageConfig.init(
    //   androidOptions: AndroidOptions(
    //     resetOnError: true,
    //     encryptedSharedPreferences: false
    //   )
    // );

    // Add any other initialization here
    // await _initializeDatabase();
    // await _setupNotifications();
    // await _configureAnalytics();

    FirebaseCrashlytics.instance.log('App setup completed');

    if (kDebugMode) {
      print('✅ App setup completed successfully');
    }
  } catch (error, stackTrace) {
    // Log setup errors
    await FirebaseCrashlytics.instance.recordError(
      error,
      stackTrace,
      reason: 'App setup failed',
      fatal: true,
    );

    if (kDebugMode) {
      print('❌ Setup error: $error');
      print('Stack trace: $stackTrace');
    }

    rethrow;
  }
}
