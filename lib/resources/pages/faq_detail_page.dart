import 'package:flutter/material.dart';
import 'package:nylo_framework/nylo_framework.dart';

class FaqDetailPage extends NyStatefulWidget {
  static RouteView path = ("/faq-detail", (_) => FaqDetailPage());

  FaqDetailPage({super.key}) : super(child: () => _FaqDetailPageState());
}

class _FaqDetailPageState extends NyPage<FaqDetailPage> {
  Map<String, dynamic> faqData = {};
  @override
  get init => () {
        faqData = widget.data() ?? {};
      };

  @override
  Widget view(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
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
            centerTitle: false,
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Text(
              "FAQ",
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
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                faqData['question'] ?? "FAQ Question",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              SizedBox(height: 16),
              Text(
                faqData['answer'] ?? "FAQ Answer",
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
