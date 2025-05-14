import 'package:flutter/material.dart';
import 'package:nylo_framework/nylo_framework.dart';

class LegalPage extends NyStatefulWidget {
  static RouteView path = ("/legal", (_) => LegalPage());

  LegalPage({super.key}) : super(child: () => _LegalPageState());
}

class _LegalPageState extends NyPage<LegalPage> {
  final List<Map<String, dynamic>> legalItems = [
    {
      'icon': Icons.lock_outline,
      'title': 'Private Policy',
      'route': '/privacy-policy'
    },
    {
      'icon': Icons.description_outlined,
      'title': 'Terms and Conditions',
      'route': '/terms-conditions'
    },
  ];
  @override
  get init => () {};

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
                color: Colors.grey.withOpacity(0.3),
                spreadRadius: 1,
                blurRadius: 6,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: AppBar(
            centerTitle: false,
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Text(
              "Legal",
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
      body: ListView.separated(
        itemCount: legalItems.length,
        separatorBuilder: (context, index) => Divider(height: 1),
        itemBuilder: (context, index) {
          final item = legalItems[index];
          return ListTile(
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Icon(item['icon'], size: 24),
            title: Text(
              item['title'],
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w400,
              ),
            ),
            trailing: Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              // Navigate to the respective page
              routeTo(item['route']);
            },
          );
        },
      ),
    );
  }
}
