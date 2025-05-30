import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

class ErrorLogger {
  static final FirebaseCrashlytics _crashlytics = FirebaseCrashlytics.instance;

  // Log non-fatal errors
  static Future<void> logError(
    dynamic error,
    StackTrace? stackTrace, {
    String? reason,
    Map<String, dynamic>? context,
    String? userId,
  }) async {
    // Print to console in debug mode
    if (kDebugMode) {
      print('🔴 Error: $error');
      print('📍 Reason: $reason');
      print('🔍 Context: $context');
      if (stackTrace != null) {
        print('📚 Stack: $stackTrace');
      }
    }

    // Set context data
    if (context != null) {
      context.forEach((key, value) {
        _crashlytics.setCustomKey(key, value.toString());
      });
    }

    if (userId != null) {
      await _crashlytics.setUserIdentifier(userId);
    }

    // Record to Crashlytics
    await _crashlytics.recordError(
      error,
      stackTrace,
      reason: reason,
      fatal: false,
    );
  }

  // Log fatal errors
  static Future<void> logFatalError(
    dynamic error,
    StackTrace? stackTrace, {
    String? reason,
  }) async {
    if (kDebugMode) {
      print('💀 Fatal Error: $error');
      print('📍 Reason: $reason');
    }

    await _crashlytics.recordError(
      error,
      stackTrace,
      reason: reason,
      fatal: true,
    );
  }

  // Log custom events/breadcrumbs
  static void logEvent(String message, {Map<String, dynamic>? data}) {
    if (kDebugMode) {
      print('📝 Event: $message - Data: $data');
    }

    String logMessage = message;
    if (data != null) {
      logMessage += ' - ${data.toString()}';
    }

    _crashlytics.log(logMessage);
  }

  // Set user context
  static Future<void> setUserContext({
    String? userId,
    String? email,
    Map<String, dynamic>? userData,
  }) async {
    if (userId != null) {
      await _crashlytics.setUserIdentifier(userId);
    }

    if (email != null) {
      _crashlytics.setCustomKey('user_email', email);
    }

    if (userData != null) {
      userData.forEach((key, value) {
        _crashlytics.setCustomKey('user_$key', value.toString());
      });
    }
  }
}
