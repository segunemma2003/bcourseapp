import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nylo_framework/nylo_framework.dart';

import '../../app/models/course.dart';
import 'featured_course_card_widget.dart';

class FeaturedCourseCarousel extends StatefulWidget {
  final List<Course> courses;
  final Duration autoScrollDuration;

  const FeaturedCourseCarousel({
    Key? key,
    required this.courses,
    this.autoScrollDuration = const Duration(seconds: 5),
  }) : super(key: key);

  @override
  createState() => _FeaturedCourseCarouselState();
}

class _FeaturedCourseCarouselState extends NyState<FeaturedCourseCarousel> {
  late PageController _pageController;
  Timer? _autoScrollTimer;
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    _autoScrollTimer?.cancel();
    super.dispose();
  }

  void _startAutoScroll() {
    _autoScrollTimer = Timer.periodic(widget.autoScrollDuration, (timer) {
      if (_pageController.hasClients) {
        _currentPage += 1;
        _pageController.animateToPage(
          _currentPage,
          duration: Duration(milliseconds: 800),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  get init => () async {
        super.init();
        int initialPage = 1000;
        _currentPage = initialPage;
        _pageController = PageController(initialPage: initialPage);

        _startAutoScroll();
      };

  @override
  Widget view(BuildContext context) {
    return Column(
      children: [
        // Full width carousel with no horizontal margins
        Container(
          height: 180,
          width: MediaQuery.of(context).size.width,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentPage = index;
              });
            },
            // Use modulo to wrap around the list of courses
            itemBuilder: (context, index) {
              final itemIndex = index % widget.courses.length;
              return FeaturedCourseCard(course: widget.courses[itemIndex]);
            },
          ),
        ),

        SizedBox(height: 8),

        // Indicator dots - always show the correct dot for the current course
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            widget.courses.length,
            (index) => Container(
              width: 8,
              height: 8,
              margin: EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _currentPage % widget.courses.length == index
                    ? Colors.amber
                    : Colors.grey[300],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
