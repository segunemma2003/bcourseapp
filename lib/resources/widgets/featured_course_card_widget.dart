import 'package:flutter/material.dart';
import 'package:flutter_app/app/models/course.dart';
import 'package:flutter_app/resources/pages/course_detail_page.dart';
import 'package:nylo_framework/nylo_framework.dart';

class FeaturedCourseCard extends StatelessWidget {
  final Course course;

  const FeaturedCourseCard({Key? key, required this.course}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        routeTo(CourseDetailPage.path, data: {'course': course});
      },
      child: Container(
        width: MediaQuery.of(context).size.width,
        height: 140, // Reduced height to make it more rectangular
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withValues(alpha: .1),
              spreadRadius: 1,
              blurRadius: 5,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius:
              BorderRadius.circular(0), // Adjust if you want rounded corners
          child: Image.network(
            course.image,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (context, error, stackTrace) {
              return Image.asset(
                'assets/images/profile_image.png',
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ).localAsset();
            },
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Center(child: CircularProgressIndicator());
            },
          ),
        ),
      ),
    );
  }
}
