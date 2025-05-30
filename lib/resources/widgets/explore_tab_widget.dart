import 'package:flutter/material.dart';
import 'package:flutter_app/app/models/course.dart';
import 'package:flutter_app/resources/pages/notifications_page.dart';
import 'package:nylo_framework/nylo_framework.dart';

import '../../app/helpers/error_logger.dart';
import '../../app/networking/course_api_service.dart';
import '../../utils/system_util.dart';
import 'course_card_widget.dart';
import 'course_tile_widget.dart';
import 'featured_course_carousel_widget.dart';

class ExploreTab extends StatefulWidget {
  static const String state = 'explore_tab';
  const ExploreTab({super.key});

  @override
  createState() => _ExploreTabState();
}

class _ExploreTabState extends NyState<ExploreTab> {
  List<Course> featuredCourses = [];
  List<Course> topCourses = [];
  List<Course> allCourses = []; // Store all courses directly for better control
  bool _isFeaturedLoading = true;
  bool _isTopCoursesLoading = true;
  bool _isAllCoursesLoading = true;
  dynamic userData;

  // API service
  CourseApiService _courseApiService = CourseApiService();

  _ExploreTabState() {
    stateName = ExploreTab.state;
  }

  @override
  LoadingStyle get loadingStyle => LoadingStyle.skeletonizer();

  @override
  get stateActions => {
        "refresh_featured_courses": () async {
          await _loadFeaturedCoursesForce();
        },
        "refresh_top_courses": () async {
          await _loadTopCoursesForce();
        },
        "refresh_all_courses": () async {
          await _loadAllCoursesForce();
        },
        "refresh_all": () {
          reboot();
        },
      };

  @override
  get init => () async {
        // Load user data
        userData = await Auth.data();

        // Load all course types in parallel
        await Future.wait([
          _loadFeaturedCourses(),
          _loadTopCourses(),
          _loadAllCourses(),
        ]);
      };

  Future<void> _loadFeaturedCourses() async {
    try {
      setState(() => _isFeaturedLoading = true);

      // Get data from API and map to Course objects
      var apiResponse =
          await _courseApiService.getFeaturedCourses(refresh: true);

      // Map the API response to List<Course>
      featuredCourses = apiResponse
          .map<Course>((courseData) => Course.fromJson(courseData))
          .toList();

      setState(() => _isFeaturedLoading = false);
    } catch (error, stackTrace) {
      NyLogger.error('Error loading featured courses: ${error.toString()}');
      await ErrorLogger.logError(error, stackTrace);
      setState(() => _isFeaturedLoading = false);
    }
  }

  Future<void> _loadFeaturedCoursesForce() async {
    try {
      setState(() => _isFeaturedLoading = true);

      // Get data from API and map to Course objects
      var apiResponse = await _courseApiService.getFeaturedCourses();

      // Map the API response to List<Course>
      featuredCourses = apiResponse
          .map<Course>((courseData) => Course.fromJson(courseData))
          .toList();

      setState(() => _isFeaturedLoading = false);
    } catch (error, stackTrace) {
      NyLogger.error('Error loading featured courses: ${error.toString()}');
      await ErrorLogger.logError(error, stackTrace);
      setState(() => _isFeaturedLoading = false);
    }
  }

  Future<void> _loadTopCourses() async {
    try {
      setState(() => _isTopCoursesLoading = true);

      // Get data from API and map to Course objects
      var apiResponse = await _courseApiService.getTopCourses(refresh: true);

      // Map the API response to List<Course>
      topCourses = apiResponse
          .map<Course>((courseData) => Course.fromJson(courseData))
          .toList();

      setState(() => _isTopCoursesLoading = false);
    } catch (e, s) {
      await ErrorLogger.logError(e, s);
      NyLogger.error('Error loading top courses: ${e.toString()}');
      setState(() => _isTopCoursesLoading = false);
    }
  }

  Future<void> _loadTopCoursesForce() async {
    try {
      setState(() => _isTopCoursesLoading = true);

      // Get data from API and map to Course objects
      var apiResponse = await _courseApiService.getTopCourses();

      // Map the API response to List<Course>
      topCourses = apiResponse
          .map<Course>((courseData) => Course.fromJson(courseData))
          .toList();

      setState(() => _isTopCoursesLoading = false);
    } catch (e, s) {
      await ErrorLogger.logError(e, s);
      NyLogger.error('Error loading top courses: ${e.toString()}');
      setState(() => _isTopCoursesLoading = false);
    }
  }

  Future<void> _loadAllCourses() async {
    try {
      setState(() => _isAllCoursesLoading = true);

      // Get data from API and map to Course objects
      var apiResponse = await _courseApiService.getAllCourses(refresh: true);

      // Map the API response to List<Course> and take only the latest 10
      List<Course> courses = apiResponse
          .map<Course>((courseData) => Course.fromJson(courseData))
          .toList();

      // Sort by date if available, or just take the first 10
      if (courses.isNotEmpty) {
        courses.sort((a, b) => b.dateUploaded.compareTo(a.dateUploaded));
      }

      // Take only the first 10 courses
      allCourses = courses.take(10).toList();

      setState(() => _isAllCoursesLoading = false);
    } catch (e) {
      NyLogger.error('Error loading all courses: ${e.toString()}');
      setState(() => _isAllCoursesLoading = false);
    }
  }

  Future<void> _loadAllCoursesForce() async {
    try {
      setState(() => _isAllCoursesLoading = true);

      // Get data from API and map to Course objects
      var apiResponse = await _courseApiService.getAllCourses();

      // Map the API response to List<Course> and take only the latest 10
      List<Course> courses = apiResponse
          .map<Course>((courseData) => Course.fromJson(courseData))
          .toList();

      // Sort by date if available, or just take the first 10
      if (courses.isNotEmpty) {
        courses.sort((a, b) => b.dateUploaded.compareTo(a.dateUploaded));
      }

      // Take only the first 10 courses
      allCourses = courses.take(10).toList();

      setState(() => _isAllCoursesLoading = false);
    } catch (e) {
      NyLogger.error('Error loading all courses: ${e.toString()}');
      setState(() => _isAllCoursesLoading = false);
    }
  }

  @override
  Widget view(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome header with profile info
            _buildWelcomeHeader(),

            // The rest of the content in a scrollable area
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  // Refresh user data
                  userData = await Auth.data();

                  // Refresh all course data
                  await Future.wait([
                    _loadFeaturedCourses(),
                    _loadTopCourses(),
                    _loadAllCourses(),
                  ]);

                  showToastSuccess(
                    description: 'Courses updated successfully!',
                  );
                },
                child: SingleChildScrollView(
                  physics: AlwaysScrollableScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Featured courses section
                        _buildSectionHeader('Featured Bhavani courses'),
                        SizedBox(height: 12),

                        // Featured courses carousel with loading state
                        _isFeaturedLoading
                            ? _buildCarouselPlaceholder()
                            : featuredCourses.isEmpty
                                ? _buildEmptyState(
                                    'No featured courses available')
                                : SizedBox(
                                    height: 200, // Fix the height
                                    width: MediaQuery.of(context).size.width,
                                    child: LayoutBuilder(
                                      builder: (context, constraints) {
                                        return FeaturedCourseCarousel(
                                          courses: featuredCourses,
                                          // If your FeaturedCourseCarousel accepts a width parameter, pass it
                                          // width: constraints.maxWidth,
                                        );
                                      },
                                    ),
                                  ),

                        SizedBox(height: 24),

                        // Top Courses section
                        _buildSectionHeader('Top Bhavani Courses'),
                        SizedBox(height: 16),

                        // Top courses horizontal list with loading state
                        _isTopCoursesLoading
                            ? _buildHorizontalListPlaceholder()
                            : topCourses.isEmpty
                                ? _buildEmptyState('No top courses available')
                                : _buildHorizontalCourseList(topCourses),

                        SizedBox(height: 24),

                        // All Bhavani Courses section - now using a direct ListView
                        _buildSectionHeader('Latest Bhavani Courses'),
                        SizedBox(height: 16),

                        // Display only the latest 10 courses directly
                        _isAllCoursesLoading
                            ? _buildVerticalListPlaceholder()
                            : allCourses.isEmpty
                                ? _buildEmptyState('No courses available yet')
                                : _buildLatestCoursesList(allCourses),

                        // Add padding at the bottom for better UX
                        SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      // Add a refresh button to the bottom right
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          // Refresh user data
          userData = await Auth.data();

          // Refresh all data
          reboot(); // This will re-run init() which loads all course types

          showToastSuccess(
            description: 'Refreshing courses...',
          );
        },
        child: Icon(Icons.refresh),
        backgroundColor: const Color(0xFFFFEB3B),
        foregroundColor: Colors.black,
      ),
    );
  }

  // UI Components

  Widget _buildWelcomeHeader() {
    String apiBaseUrl = getEnv('API_BASE_URL');
    String? profilePictureUrl =
        userData != null ? userData['profile_picture_url'] : null;

    return Padding(
      padding: EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                // User avatar/profile image
                ClipOval(
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      shape: BoxShape.circle,
                    ),
                    child: profilePictureUrl != null
                        ? Image.network(
                            // Handle both relative and absolute URLs
                            profilePictureUrl.startsWith('http')
                                ? profilePictureUrl
                                : "$apiBaseUrl$profilePictureUrl",
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return _buildProfileInitial();
                            },
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  value: loadingProgress.expectedTotalBytes !=
                                          null
                                      ? loadingProgress.cumulativeBytesLoaded /
                                          loadingProgress.expectedTotalBytes!
                                      : null,
                                ),
                              );
                            },
                          )
                        : _buildProfileInitial(),
                  ),
                ),
                SizedBox(width: 12),
                // User greeting and app tagline
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Show user's name or default greeting using userData
                      Text(
                        userData != null && userData['full_name'] != null
                            ? 'Welcome, ${userData['full_name']}'
                            : 'Welcome to Bhavani',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Explore all our courses and become a top fashion designer',
                        style: TextStyle(
                          fontSize: 8,
                          color: Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Notification bell with action
          // Stack(
          //   children: [
          //     IconButton(
          //       icon: Icon(Icons.notifications_none),
          //       onPressed: () {
          //         routeTo(NotificationsPage.path);
          //       },
          //     ),
          //     // Notification dot - can be conditionally shown
          //     Positioned(
          //       top: 8,
          //       right: 8,
          //       child: Container(
          //         width: 8,
          //         height: 8,
          //         decoration: BoxDecoration(
          //           color: Colors.red,
          //           shape: BoxShape.circle,
          //         ),
          //       ),
          //     ),
          //   ],
          // ),
        ],
      ),
    );
  }

  Widget _buildProfileInitial() {
    String fullName = userData != null && userData['full_name'] != null
        ? userData['full_name']
        : '';

    return Center(
      child: Text(
        fullName.isNotEmpty ? fullName[0].toUpperCase() : 'B',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.grey[700],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildHorizontalCourseList(List<Course> courses) {
    return SizedBox(
      height: 200,
      width: MediaQuery.of(context).size.width,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 16),
        itemCount: courses.length,
        itemBuilder: (context, index) {
          return ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 185),
            child: Container(
              margin: EdgeInsets.only(right: 16),
              child: CourseCard(course: courses[index]),
            ),
          );
        },
      ),
    );
  }

  // Build the latest courses list without using NyPullToRefresh
  Widget _buildLatestCoursesList(List<Course> courses) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width,
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: NeverScrollableScrollPhysics(),
        itemCount: courses.length,
        padding: EdgeInsets.symmetric(horizontal: 16),
        separatorBuilder: (context, index) {
          return Divider(height: 1, thickness: 0.5, color: Colors.grey[200]);
        },
        itemBuilder: (context, index) {
          return CourseTile(course: courses[index]);
        },
      ),
    );
  }

  // Loading placeholders for better UX during data fetching
  Widget _buildCarouselPlaceholder() {
    return SizedBox(
      height: 200,
      width: MediaQuery.of(context).size.width,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 16),
        itemCount: 3,
        itemBuilder: (context, index) {
          return Container(
            width: 280,
            margin: EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(16),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHorizontalListPlaceholder() {
    return SizedBox(
      height: 200,
      width: MediaQuery.of(context).size.width,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 16),
        itemCount: 4,
        itemBuilder: (context, index) {
          return Container(
            width: 150,
            margin: EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
            ),
          );
        },
      ),
    );
  }

  Widget _buildVerticalListPlaceholder() {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width,
      ),
      child: ListView.builder(
        shrinkWrap: true,
        physics: NeverScrollableScrollPhysics(),
        itemCount: 5,
        padding: EdgeInsets.symmetric(horizontal: 16),
        itemBuilder: (context, index) {
          return Container(
            height: 80,
            margin: EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Container(
      width: MediaQuery.of(context).size.width,
      padding: EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(
            Icons.shopping_bag_outlined,
            size: 48,
            color: Colors.grey[400],
          ),
          SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
