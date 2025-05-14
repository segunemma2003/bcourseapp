import '/app/models/objectives.dart';
import '/app/models/curriculum.dart';
import '/app/models/requirements.dart';
import '/app/models/wishlist.dart';
import '/app/models/payment_card.dart';
import '/app/models/purchase_history.dart';
import '/app/models/enrollment.dart';
import '/app/models/category.dart';
import '/app/networking/notification_api_service.dart';
import '/app/networking/purchase_api_service.dart';
import '/app/networking/card_api_service.dart';
import '/app/networking/category_api_service.dart';
import '/app/networking/course_api_service.dart';
import '/app/networking/user_api_service.dart';
import '/app/models/notification.dart';
import '/app/models/course.dart';
import '/app/controllers/home_controller.dart';
import '/app/models/user.dart';
import '/app/networking/api_service.dart';

/* Model Decoders
|--------------------------------------------------------------------------
| Model decoders are used in 'app/networking/' for morphing json payloads
| into Models.
|
| Learn more https://nylo.dev/docs/6.x/decoders#model-decoders
|-------------------------------------------------------------------------- */

final Map<Type, dynamic> modelDecoders = {
  Map<String, dynamic>: (data) => Map<String, dynamic>.from(data),

  List<User>: (data) =>
      List.from(data).map((json) => User.fromJson(json)).toList(),
  //
  User: (data) => User.fromJson(data),

  // User: (data) => User.fromJson(data),

  List<Course>: (data) =>
      List.from(data).map((json) => Course.fromJson(json)).toList(),

  Course: (data) => Course.fromJson(data),

  List<NotificationModel>: (data) =>
      List.from(data).map((json) => NotificationModel.fromJson(json)).toList(),

  NotificationModel: (data) => NotificationModel.fromJson(data),

  List<Category>: (data) => List.from(data).map((json) => Category.fromJson(json)).toList(),

  Category: (data) => Category.fromJson(data),

  List<Enrollment>: (data) => List.from(data).map((json) => Enrollment.fromJson(json)).toList(),

  Enrollment: (data) => Enrollment.fromJson(data),

  List<PurchaseHistory>: (data) => List.from(data).map((json) => PurchaseHistory.fromJson(json)).toList(),

  PurchaseHistory: (data) => PurchaseHistory.fromJson(data),

  List<PaymentCard>: (data) => List.from(data).map((json) => PaymentCard.fromJson(json)).toList(),

  PaymentCard: (data) => PaymentCard.fromJson(data),

  List<Wishlist>: (data) => List.from(data).map((json) => Wishlist.fromJson(json)).toList(),

  Wishlist: (data) => Wishlist.fromJson(data),

  List<Requirements>: (data) => List.from(data).map((json) => Requirements.fromJson(json)).toList(),

  Requirements: (data) => Requirements.fromJson(data),

  List<Curriculum>: (data) => List.from(data).map((json) => Curriculum.fromJson(json)).toList(),

  Curriculum: (data) => Curriculum.fromJson(data),

  List<Objectives>: (data) => List.from(data).map((json) => Objectives.fromJson(json)).toList(),

  Objectives: (data) => Objectives.fromJson(data),
};

/* API Decoders
| -------------------------------------------------------------------------
| API decoders are used when you need to access an API service using the
| 'api' helper. E.g. api<MyApiService>((request) => request.fetchData());
|
| Learn more https://nylo.dev/docs/6.x/decoders#api-decoders
|-------------------------------------------------------------------------- */

final Map<Type, dynamic> apiDecoders = {
  ApiService: () => ApiService(),

  // ...

  UserApiService: UserApiService(),

  CourseApiService: CourseApiService(),

  CategoryApiService: CategoryApiService(),

  CardApiService: CardApiService(),

  PurchaseApiService: PurchaseApiService(),

  NotificationApiService: NotificationApiService(),
};

/* Controller Decoders
| -------------------------------------------------------------------------
| Controller are used in pages.
|
| Learn more https://nylo.dev/docs/6.x/controllers
|-------------------------------------------------------------------------- */
final Map<Type, dynamic> controllers = {
  HomeController: () => HomeController(),

  // ...
};
