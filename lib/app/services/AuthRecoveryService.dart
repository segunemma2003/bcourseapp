import 'package:nylo_framework/nylo_framework.dart';

class AuthRecoveryService {
  /// Call this method in your app's initialization
  static Future<bool> recoverAuthenticationState() async {
    try {
      // Check if we have stored auth token
      final authToken = await backpackRead('auth_token');

      if (authToken == null) {
        return false;
      }

      // Check if we have stored user data
      final userData = await storageRead("user");

      if (userData == null) {
        // Token exists but no user data - invalid state
        await _clearInvalidAuthState();
        return false;
      }

      // Check if Auth framework recognizes the user
      bool isAuthenticated = await Auth.isAuthenticated();

      if (!isAuthenticated) {
        // Re-authenticate using stored user data
        await Auth.authenticate(data: userData);
        NyLogger.info('Authentication state recovered successfully');
      }

      return true;
    } catch (e) {
      NyLogger.error('Failed to recover authentication state: $e');
      await _clearInvalidAuthState();
      return false;
    }
  }

  static Future<void> _clearInvalidAuthState() async {
    try {
      await backpackDelete('auth_token');
      await storageDelete("user");
      await Auth.logout();
      NyLogger.info('Cleared invalid authentication state');
    } catch (e) {
      NyLogger.error('Error clearing invalid auth state: $e');
    }
  }

  /// Validate that the stored token is still valid with the backend
  static Future<bool> validateStoredToken() async {
    try {
      final authToken = await backpackRead('auth_token');

      if (authToken == null) {
        return false;
      }

      // You can make a simple API call to verify the token
      // For example, call your getCurrentUser() method
      // If it succeeds, the token is valid
      // If it fails, clear the auth state

      return true;
    } catch (e) {
      NyLogger.error('Token validation failed: $e');
      await _clearInvalidAuthState();
      return false;
    }
  }
}
