import 'package:flutter/material.dart';
import 'package:flutter_app/app/models/notification.dart';
import 'package:nylo_framework/nylo_framework.dart';

import '../../utils/notification_data.dart';
import '../widgets/notification_card_widget.dart';

class NotificationsPage extends NyStatefulWidget {
  static RouteView path = ("/notifications", (_) => NotificationsPage());

  NotificationsPage({super.key})
      : super(child: () => _NotificationsPageState());
}

class _NotificationsPageState extends NyPage<NotificationsPage> {
  List<NotificationModel> notifications = [];

  @override
  get init => () async {
        setLoading(true);

        // Initialize notifications from data service
        notifications = await NotificationData.fetchNotificationsFromAPI();

        // Set loading state to false
        setLoading(false);
      };

  @override
  Widget view(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Notifications',
          style: TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: false, // This aligns the title to the left
        titleSpacing: 0, // Reduces space between back button and title
      ),
      body: afterLoad(
        child: () {
          if (notifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_off_outlined,
                    size: 72,
                    color: Colors.grey[400],
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No notifications',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: EdgeInsets.only(top: 16),
            itemCount: notifications.length,
            separatorBuilder: (context, index) => SizedBox(height: 1),
            itemBuilder: (context, index) {
              return NotificationCard(
                notification: notifications[index],
                onTap: () async {
                  // In a real app, you would navigate to the appropriate page
                  // and mark the notification as read
                  setState(() {
                    notifications[index] = NotificationModel(
                      title: notifications[index].title,
                      message: notifications[index].message,
                      date: notifications[index].date,
                      isUnread: false,
                    );
                  });
                },
              );
            },
          );
        },
      ),
    );
  }
}
