import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'package:url_launcher/url_launcher.dart';

class HelpCenterPage extends NyStatefulWidget {
  static RouteView path = ("/help-center", (_) => HelpCenterPage());

  HelpCenterPage({super.key}) : super(child: () => _HelpCenterPageState());
}

class _HelpCenterPageState extends NyPage<HelpCenterPage> {
  List<Map<String, dynamic>> _helpOptions = [];

  @override
  get init => () async {
        await _fetchHelpOptions();
      };

  Future<void> _fetchHelpOptions() async {
    setLoading(true);

    try {
      // In a real app, fetch help options from config or API
      await Future.delayed(Duration(milliseconds: 500));

      setState(() {
        _helpOptions = [
          {
            'id': '1',
            'title': 'Whatsapp',
            'icon': FontAwesomeIcons.whatsapp,
            'action': 'whatsapp',
            'value': '+919876543210',
          },
          {
            'id': '2',
            'title': 'Email',
            'icon': Icons.email_outlined,
            'action': 'email',
            'value': 'support@example.com',
          },
        ];
      });
    } catch (e) {
      NyLogger.error('Failed to fetch help options: $e');
      showToast(
        title: trans("Error"),
        description: trans("Failed to load help options"),
        icon: Icons.error_outline,
        style: ToastNotificationStyleType.danger,
      );
    } finally {
      setLoading(false);
    }
  }

  Future<void> _handleContactOption(Map<String, dynamic> option) async {
    try {
      switch (option['action']) {
        case 'whatsapp':
          final whatsappUrl = "https://wa.me/${option['value']}";
          await _launchUrl(whatsappUrl);
          break;
        case 'email':
          final emailUrl = "mailto:${option['value']}";
          await _launchUrl(emailUrl);
          break;
        default:
          NyLogger.error('Unknown contact option: ${option['action']}');
      }
    } catch (e) {
      NyLogger.error('Failed to handle contact option: $e');
      showToast(
        title: trans("Error"),
        description: trans("Failed to open contact method"),
        icon: Icons.error_outline,
        style: ToastNotificationStyleType.danger,
      );
    }
  }

  Future<void> _launchUrl(String url) async {
    if (await canLaunch(url)) {
      await launch(url);
    } else {
      throw 'Could not launch $url';
    }
  }

  @override
  Widget view(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(56),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withValues(alpha: .3),
                spreadRadius: 1,
                blurRadius: 6,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Text(
              "Get Help",
              style: TextStyle(
                color: Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: Colors.black),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
      ),
      body: Column(
        children:
            _helpOptions.map((option) => _buildContactOption(option)).toList(),
      ),
    );
  }

  Widget _buildContactOption(Map<String, dynamic> option) {
    IconData iconData = Icons.help_outline;

    // Map string action to appropriate icon if needed
    if (option['action'] == 'whatsapp') {
      iconData = FontAwesomeIcons.whatsapp;
    } else if (option['action'] == 'email') {
      iconData = Icons.email_outlined;
    } else if (option['icon'] != null) {
      iconData = option['icon'];
    }

    return InkWell(
      onTap: () => _handleContactOption(option),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade200, width: 1),
          ),
        ),
        child: Row(
          children: [
            Icon(iconData, size: 24, color: Colors.black87),
            SizedBox(width: 16),
            Text(
              option['title'],
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: Colors.black87,
              ),
            ),
            Spacer(),
            Icon(Icons.arrow_forward, size: 16, color: Colors.black),
          ],
        ),
      ),
    );
  }
}
