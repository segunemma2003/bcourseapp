import 'package:flutter_app/resources/pages/signin_page.dart';
import 'package:nylo_framework/nylo_framework.dart';

/* Dashboard Route Guard
|-------------------------------------------------------------------------- */

class DashboardRouteGuard extends NyRouteGuard {
  DashboardRouteGuard();

  @override
  onRequest(PageRequest pageRequest) async {
    // example
    bool userLoggedIn = await Auth.isAuthenticated();
    final authToken = await backpackRead('auth_token');

    if (userLoggedIn == false || authToken == null) {
      return redirect(SigninPage.path);
    }

    return pageRequest;
  }
}
