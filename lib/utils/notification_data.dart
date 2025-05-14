// lib/utils/notification_data.dart
import '../../app/models/notification.dart';

class NotificationData {
  static List<NotificationModel> getNotifications() {
    return [
      NotificationModel(
        title: 'Jump right back in',
        message:
            'Continue your work in Full Boutique Start Up Course - Zero to Master Class',
        date: '07/04/25',
        isUnread: true,
      ),
      NotificationModel(
        title: 'Jump right back in',
        message:
            'Continue your work in Full Boutique Start Up Course - Zero to Master Class',
        date: '07/04/25',
        isUnread: true,
      ),
      NotificationModel(
        title: 'Jump right back in',
        message:
            'Continue your work in Full Boutique Start Up Course - Zero to Master Class',
        date: '07/04/25',
        isUnread: true,
      ),
      NotificationModel(
        title: 'Jump right back in',
        message:
            'Continue your work in Full Boutique Start Up Course - Zero to Master Class',
        date: '07/04/25',
        isUnread: false,
      ),
    ];
  }

  // You can add more methods for managing notifications
  static Future<List<NotificationModel>> fetchNotificationsFromAPI() async {
    // In a real app, you would fetch from an API
    // For now, we'll just return the sample data
    // await Future.delayed(Duration(seconds: 1)); // Simulate network delay
    return getNotifications();
  }

  static Future<void> markAsRead(String notificationId) async {
    // Logic to mark a notification as read
    // This would typically update a local database or call an API
    await Future.delayed(Duration(milliseconds: 300));
    return;
  }

  static Future<void> clearAllNotifications() async {
    // Logic to clear all notifications
    await Future.delayed(Duration(milliseconds: 300));
    return;
  }
}
