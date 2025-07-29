import '/resources/pages/new_password_page.dart';
import '/resources/pages/verify_o_t_p_page.dart';
import '/resources/pages/video_player_page.dart';
import '/resources/pages/forgot_password_page.dart';
import '/resources/pages/legal_page.dart';
import '/resources/pages/privacy_policy_page.dart';
import '/resources/pages/terms_conditions_page.dart';
import '/resources/pages/faq_detail_page.dart';
import '/resources/pages/faq_page.dart';
import '/resources/pages/help_center_page.dart';
import '/resources/pages/purchase_history_page.dart';
import '/resources/pages/payment_details_page.dart';
import '/resources/pages/profile_details_page.dart';
import '/resources/pages/signin_page.dart';
import '/resources/pages/course_detail_wishlist_page.dart';
import '/resources/pages/course_video_player_page.dart';
import '/resources/pages/purchased_course_detail_page.dart';
import 'package:flutter_app/resources/pages/course_curriculum_page.dart';
import 'package:flutter_app/resources/pages/course_detail_page.dart';
import 'package:flutter_app/resources/pages/enrollment_plan_page.dart';
import 'package:flutter_app/resources/pages/notifications_page.dart';

import '/resources/pages/base_navigation_hub.dart';
import '/resources/pages/sign_up_page.dart';
import '/resources/pages/not_found_page.dart';
import 'package:nylo_framework/nylo_framework.dart';

import 'guards/dashboard_route_guard.dart';

/* App Router
|--------------------------------------------------------------------------
| * [Tip] Create pages faster 🚀
| Run the below in the terminal to create new a page.
| "dart run nylo_framework:main make:page profile_page"
|
| * [Tip] Add authentication 🔑
| Run the below in the terminal to add authentication to your project.
| "dart run scaffold_ui:main auth"
|
| * [Tip] Add In-app Purchases 💳
| Run the below in the terminal to add In-app Purchases to your project.
| "dart run scaffold_ui:main iap"
|
| Learn more https://nylo.dev/docs/6.x/router
|-------------------------------------------------------------------------- */

appRouter() => nyRoutes((router) {
      router.add(SignUpPage.path);

      // Add your routes here ...
      // router.add(NewPage.path, transitionType: TransitionType.fade());

      // Example using grouped routes
      // router.group(() => {
      //   "route_guards": [AuthRouteGuard()],
      //   "prefix": "/dashboard"
      // }, (router) {
      //
      // });
      router.add(NotFoundPage.path).unknownRoute();
      router.add(BaseNavigationHub.path, routeGuards: [
        DashboardRouteGuard() // Add your guard
      ]).initialRoute();
      router.add(CourseCurriculumPage.path);
      router.add(CourseDetailPage.path);
      router.add(EnrollmentPlanPage.path);

      router.add(NotificationsPage.path);
      router.add(PurchasedCourseDetailPage.path);
      router.add(CourseVideoPlayerPage.path);
      router.add(CourseDetailWishlistPage.path);
      router.add(SigninPage.path);
      router.add(ProfileDetailsPage.path);
      router.add(PaymentDetailsPage.path);
      router.add(PurchaseHistoryPage.path);
      router.add(HelpCenterPage.path);
      router.add(FaqPage.path);
      router.add(FaqDetailPage.path);
      router.add(LegalPage.path);
      router.add(PrivacyPolicyPage.path);
      router.add(TermsConditionsPage.path);
      router.add(ForgotPasswordPage.path);
      router.add(VideoPlayerPage.path);
      router.add(VerifyOTPPage.path);
      router.add(NewPasswordPage.path);
    });
