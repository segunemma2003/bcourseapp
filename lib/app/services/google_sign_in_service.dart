import 'package:google_sign_in/google_sign_in.dart';
import 'package:nylo_framework/nylo_framework.dart';

class GoogleSignInService {
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'profile',
    ],
    // Add your web client ID here (optional but recommended for web support)
    // clientId: 'YOUR_WEB_CLIENT_ID',
  );

  // Initialize Google Sign-In (call this in your app's initialization)
  static Future<void> initialize() async {
    // You can configure additional settings here if needed
  }

  // Sign in with Google
  static Future<GoogleSignInAccount?> signIn() async {
    try {
      final GoogleSignInAccount? account = await _googleSignIn.signIn();
      return account;
    } catch (error) {
      print('Google Sign-In Error: $error');
      rethrow;
    }
  }

  // Sign out
  static Future<void> signOut() async {
    await _googleSignIn.signOut();
  }

  // Get current signed-in user
  static GoogleSignInAccount? getCurrentUser() {
    return _googleSignIn.currentUser;
  }

  // Check if user is already signed in
  static Future<GoogleSignInAccount?> silentSignIn() async {
    try {
      return await _googleSignIn.signInSilently();
    } catch (error) {
      print('Silent sign-in failed: $error');
      return null;
    }
  }

  // Get authentication tokens
  static Future<GoogleSignInAuthentication?> getAuthentication(
      GoogleSignInAccount account) async {
    return await account.authentication;
  }

  // Disconnect (revokes access)
  static Future<void> disconnect() async {
    await _googleSignIn.disconnect();
  }
}
