import 'package:nylo_framework/nylo_framework.dart';

class NotificationModel extends Model {
  final String title;
  final String message;
  final String date;
  final bool isUnread;

  static String storageKey = "notification_model";

  NotificationModel({
    required this.title,
    required this.message,
    required this.date,
    this.isUnread = false,
  }) : super(key: storageKey);

  NotificationModel.fromJson(dynamic data)
      : title = data['title'] ?? '',
        message = data['message'] ?? '',
        date = data['date'] ?? '',
        isUnread = data['isUnread'] ?? false,
        super(key: storageKey);

  @override
  toJson() {
    return {
      'title': title,
      'message': message,
      'date': date,
      'isUnread': isUnread,
    };
  }
}
