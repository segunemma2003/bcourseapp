// app/services/error_logging_service.dart
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:nylo_framework/nylo_framework.dart';

class ErrorLoggingService {
  static final FirebaseCrashlytics _crashlytics = FirebaseCrashlytics.instance;

  // Log non-fatal errors
  static Future<void> logError(
    dynamic error,
    StackTrace? stackTrace, {
    String? reason,
    Map<String, dynamic>? additionalData,
  }) async {
    // Log to console in debug mode
    if (kDebugMode) {
      print('Error: $error');
      print('StackTrace: $stackTrace');
      print('Reason: $reason');
      print('Additional Data: $additionalData');
    }

    // Set custom keys for better context
    if (additionalData != null) {
      additionalData.forEach((key, value) {
        _crashlytics.setCustomKey(key, value.toString());
      });
    }

    if (reason != null) {
      _crashlytics.setCustomKey('error_reason', reason);
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
    await _crashlytics.recordError(
      error,
      stackTrace,
      reason: reason,
      fatal: true,
    );
  }

  // Set user information
  static Future<void> setUserInfo({
    String? userId,
    String? email,
    String? name,
  }) async {
    if (userId != null) await _crashlytics.setUserIdentifier(userId);
    if (email != null) await _crashlytics.setCustomKey('user_email', email);
    if (name != null) await _crashlytics.setCustomKey('user_name', name);
  }

  // Log custom events
  static Future<void> logEvent(
      String event, Map<String, dynamic> parameters) async {
    _crashlytics.log('Event: $event - Parameters: $parameters');
  }

  // Test crash (for testing purposes only)
  static void testCrash() {
    _crashlytics.crash();
  }
}
