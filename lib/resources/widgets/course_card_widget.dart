import 'package:flutter/material.dart';
import 'package:flutter_app/app/models/course.dart';
import 'package:flutter_app/resources/pages/course_detail_page.dart';
import 'package:nylo_framework/nylo_framework.dart';

class CourseCard extends StatelessWidget {
  final Course course;

  const CourseCard({Key? key, required this.course}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        routeTo(CourseDetailPage.path, data: {'course': course});
      },
      child: Container(
        width: 200, // Set a fixed width for the card
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 120, // Set a fixed height for the image container
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  course.image,
                  width: double
                      .infinity, // Make image take full width of container
                  height: 120,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Image.asset(
                      'assets/images/profile_image.png',
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: 120,
                    ).localAsset();
                  },
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Center(child: CircularProgressIndicator());
                  },
                ),
              ),
            ),
            SizedBox(height: 8),
            Text(
              course.title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12, // Increased font size for better readability
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: 4),
            Text(
              course.smallDesc,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 10, // Increased font size
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: 4),
            Text(
              course.categoryName,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 10, // Increased font size
              ),
            ),
          ],
        ),
      ),
    );
  }
}
