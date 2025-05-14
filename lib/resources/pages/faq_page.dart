import 'package:flutter/material.dart';
import 'package:flutter_app/resources/pages/faq_detail_page.dart';
import 'package:nylo_framework/nylo_framework.dart';

class FaqPage extends NyStatefulWidget {
  static RouteView path = ("/faq", (_) => FaqPage());

  FaqPage({super.key}) : super(child: () => _FaqPageState());
}

class _FaqPageState extends NyPage<FaqPage> {
  final List<Map<String, dynamic>> faqs = [
    {
      'question': 'Can I get any courses for free?',
      'answer':
          'At the moment, we don\'t offer any free courses. However, we\'re working on creating a few introductory and mini-courses that may be made available at no cost in the future. That said, even for those free courses, a small fee will be required if you wish to receive a certificate of completion. Our goal is to provide high-quality, value-packed learning experiences, and certification helps validate the skills you\'ve gained. Stay tuned exciting updates are on the way!'
    },
    {
      'question': 'Can I get any courses for free?',
      'answer':
          'At the moment, we don\'t offer any free courses. However, we\'re working on creating a few introductory and mini-courses that may be made available at no cost in the future.'
    },
    {
      'question': 'Can I get any courses for free?',
      'answer': 'At the moment, we don\'t offer any free courses.'
    },
    {
      'question': 'Can I get any courses for free?',
      'answer':
          'At the moment, we don\'t offer any free courses. However, we\'re working on creating a few introductory and mini-courses that may be made available at no cost in the future.'
    },
    {
      'question': 'Can I get any courses for free?',
      'answer':
          'At the moment, we don\'t offer any free courses. However, we\'re working on creating a few introductory and mini-courses that may be made available at no cost in the future.'
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
                  "FAQs",
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                leading: IconButton(
                  icon: Icon(Icons.arrow_back, color: Colors.black),
                  onPressed: () => Navigator.pop(context),
                ))),
      ),
      body: ListView.separated(
        itemCount: faqs.length,
        separatorBuilder: (context, index) => Divider(height: 1),
        itemBuilder: (context, index) {
          return ListTile(
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            title: Text(
              faqs[index]['question'],
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
            trailing: Icon(Icons.arrow_forward, size: 16),
            onTap: () {
              routeTo(FaqDetailPage.path, data: faqs[index]);
            },
          );
        },
      ),
    );
  }
}
