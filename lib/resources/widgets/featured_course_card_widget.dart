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
        height: 180,
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
        child: Row(
          children: [
            // Left side - Image section
            Expanded(
              flex: 1,
              child: Container(
                color: Colors.green,
                child: Image.network(
                  course.image,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Image.asset(
                      'assets/images/profile_image.png',
                      fit: BoxFit.cover,
                    ).localAsset();
                  },
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Center(child: CircularProgressIndicator());
                  },
                ),
              ),
            ),

            // Right side - Text content
            Expanded(
              flex: 1,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // English title - allowing natural text wrapping
                    Text(
                      course.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        height: 1.3, // Improved line height for readability
                      ),
                      softWrap: true, // Enable text wrapping
                      overflow: TextOverflow.ellipsis,
                      maxLines: 3, // Allow up to 3 lines
                    ),

                    SizedBox(
                        height: 8), // Small space between title and subtitle

                    // Indian language subtitle
                    Text(
                      course.smallDesc,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                        height: 1.2, // Slightly tighter line height
                      ),
                      softWrap: true,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2, // Allow up to 2 lines
                    ),

                    // Spacer to push category to bottom
                    Spacer(),

                    // Category label
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        course.categoryName,
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
