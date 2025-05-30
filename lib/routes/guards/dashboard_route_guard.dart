import 'package:flutter_app/app/networking/token_helper.dart';
import 'package:flutter_app/resources/pages/signin_page.dart';
import 'package:nylo_framework/nylo_framework.dart';

class DashboardRouteGuard extends NyRouteGuard {
  DashboardRouteGuard();

  @override
  onRequest(PageRequest pageRequest) async {
    try {
      NyLogger.info('=== ROUTE GUARD DEBUG ===');

      // Check authentication state
      bool userLoggedIn = await Auth.isAuthenticated();
      final authToken =
          await TokenSyncHelper.readAuthToken(); // This will auto-sync

      NyLogger.info('Auth.isAuthenticated(): $userLoggedIn');
      NyLogger.info('Auth token exists: ${authToken != null}');

      // Simple logic: if user is authenticated and has token, allow access
      if (userLoggedIn && authToken != null) {
        NyLogger.info('Authentication check passed');
        return pageRequest;
      }

      // If user is authenticated but no token, clear everything (corrupted state)
      if (userLoggedIn && authToken == null) {
        NyLogger.error(
            'User authenticated but no token - clearing corrupted state');
        await Auth.logout();
        return redirect(SigninPage.path);
      }

      // If no authentication, redirect to signin
      NyLogger.info('No authentication - redirecting to signin');
      return redirect(SigninPage.path);
    } catch (e) {
      NyLogger.error('Route guard error: $e');
      return redirect(SigninPage.path);
    }
  }
}
