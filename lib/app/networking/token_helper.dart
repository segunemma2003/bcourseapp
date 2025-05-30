import 'package:nylo_framework/nylo_framework.dart';

/// Helper class to keep auth token in sync between NyStorage and backpack
class TokenSyncHelper {
  /// Save auth token to both NyStorage and backpack
  static Future<void> saveAuthToken(String token) async {
    try {
      // Save to NyStorage (primary)
      await NyStorage.save('auth_token', token, inBackpack: true);

      // Also save to backpack for compatibility
      await backpackSave('auth_token', token);

      NyLogger.info('Auth token saved to both storage systems');
    } catch (e) {
      NyLogger.error('Error saving auth token: $e');
      rethrow;
    }
  }

  /// Read auth token (try both methods and sync if needed)
  static Future<String?> readAuthToken() async {
    try {
      // Try NyStorage first
      String? nyToken = await NyStorage.read('auth_token');
      String? backpackToken = await backpackRead('auth_token');

      // If both exist and match, return the token
      if (nyToken != null &&
          backpackToken != null &&
          nyToken == backpackToken) {
        return nyToken;
      }

      // If NyStorage has token but backpack doesn't, sync to backpack
      if (nyToken != null && backpackToken == null) {
        await backpackSave('auth_token', nyToken);
        NyLogger.info('Synced token: NyStorage -> backpack');
        return nyToken;
      }

      // If backpack has token but NyStorage doesn't, sync to NyStorage
      if (backpackToken != null && nyToken == null) {
        await NyStorage.save('auth_token', backpackToken, inBackpack: true);
        NyLogger.info('Synced token: backpack -> NyStorage');
        return backpackToken;
      }

      // If both have different tokens, prefer NyStorage (newer API)
      if (nyToken != null &&
          backpackToken != null &&
          nyToken != backpackToken) {
        await backpackSave('auth_token', nyToken);
        NyLogger.info('Resolved token conflict: used NyStorage version');
        return nyToken;
      }

      // Return whatever token exists
      return nyToken ?? backpackToken;
    } catch (e) {
      NyLogger.error('Error reading auth token: $e');
      return null;
    }
  }

  /// Delete auth token from both storage systems
  static Future<void> clearAuthToken() async {
    try {
      await NyStorage.delete('auth_token');
      await backpackDelete('auth_token');
      NyLogger.info('Auth token cleared from both storage systems');
    } catch (e) {
      NyLogger.error('Error clearing auth token: $e');
    }
  }
}
