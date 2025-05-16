import 'package:flutter/material.dart';
import 'package:flutter_app/resources/pages/base_navigation_hub.dart';
import 'package:flutter_app/resources/pages/purchased_course_detail_page.dart';
import 'package:nylo_framework/nylo_framework.dart';

import '../../app/models/course.dart';
import '../../app/networking/course_api_service.dart';

class CoursesTab extends StatefulWidget {
  const CoursesTab({super.key});

  // Define state name for Nylo's state management
  static String state = '/courses_tab';

  @override
  createState() => _CoursesTabState();
}

class _CoursesTabState extends NyState<CoursesTab> {
  List<Course> _enrolledCourses = [];
  bool _hasCourses = false;
  bool _isAuthenticated = false;

  // Progress tracking for each course
  Map<String, double> _courseProgress = {};
  Map<String, int> _courseVideoCount = {};

  // Set state name for Nylo's state management
  _CoursesTabState() {
    stateName = CoursesTab.state;
  }

  @override
  LoadingStyle get loadingStyle => LoadingStyle.skeletonizer(
        child: _buildSkeletonLayout(),
      );

  @override
  get init => () async {
        super.init();

        // Check authentication first
        _isAuthenticated = await Auth.isAuthenticated();

        // Fetch enrolled courses
        await _fetchEnrolledCourses();

        // Load progress for each course
        await _loadCourseProgress();
      };

  @override
  stateUpdated(data) async {
    if (data == "refresh_enrolled_courses") {
      await _fetchEnrolledCourses(refresh: true);
    } else if (data == "update_auth_status") {
      setState(() {
        _isAuthenticated = true;
      });
      await _fetchEnrolledCourses(refresh: true);
    } else if (data == "update_course_progress") {
      await _loadCourseProgress();
    }

    return super.stateUpdated(data);
  }

  Future<void> _loadCourseProgress() async {
    if (_enrolledCourses.isEmpty) return;

    for (var course in _enrolledCourses) {
      try {
        // Load saved progress from storage
        String key = 'course_progress_${course.id}';

        var savedProgress = await NyStorage.read(key);

        if (savedProgress != null) {
          // Calculate progress percentage
          var completedLessons = (savedProgress is Map &&
                  savedProgress.containsKey('completedLessons'))
              ? savedProgress['completedLessons']
              : {};

          print(savedProgress);
          var completedCount =
              completedLessons.values.where((v) => v == true).length;

          // Get video counts from CourseApiService or CourseData
          var curriculumItems = await _fetchCurriculumForCourse(course.id);
          print(curriculumItems);
          int totalVideos = curriculumItems.length;

          // Calculate and save progress
          double progress =
              totalVideos > 0 ? completedCount / totalVideos : 0.0;

          setState(() {
            _courseProgress[course.id.toString()] = progress;
            _courseVideoCount[course.id.toString()] = totalVideos;
          });
        } else {
          // No progress yet, but still get video count
          List<dynamic> curriculumItems =
              await _fetchCurriculumForCourse(course.id);

          setState(() {
            _courseProgress[course.id.toString()] = 0.0;
            _courseVideoCount[course.id.toString()] = curriculumItems.length;
          });
        }
      } catch (e) {
        NyLogger.error('Failed to load progress for course ${course.id}: $e');

        // Set defaults if loading fails
        setState(() {
          _courseProgress[course.id.toString()] = 0.0;
          _courseVideoCount[course.id.toString()] = 0;
        });
      }
    }
  }

  Future<List<dynamic>> _fetchCurriculumForCourse(int courseId) async {
    // This would typically come from your API
    // For demo purposes, we'll return a list with a length based on courseId
    try {
      var courseApiService = CourseApiService();
      List<dynamic> curriculum =
          await courseApiService.getCourseCurriculum(courseId);
      return curriculum;
    } catch (e) {
      // Fallback to local data in case API fails

      return [];
    }
  }

  Future<void> _fetchEnrolledCourses({bool refresh = false}) async {
    setLoading(true, name: 'fetch_enrolled_courses');

    try {
      // If not authenticated, we can't fetch enrolled courses
      if (!_isAuthenticated) {
        setState(() {
          _enrolledCourses = [];
          _hasCourses = false;
        });
        return;
      }

      // Use the CourseApiService to fetch enrolled courses
      var courseApiService = CourseApiService();

      try {
        // Fetch enrolled courses from API
        List<dynamic> enrolledCoursesData =
            await courseApiService.getEnrolledCourses();

        // Process the courses
        if (enrolledCoursesData.isNotEmpty) {
          _enrolledCourses = enrolledCoursesData
              .map((data) => Course.fromJson(data['course']))
              .toList();
          _hasCourses = _enrolledCourses.isNotEmpty;
        } else {
          _enrolledCourses = [];
          _hasCourses = false;
        }
      } catch (e) {
        // If API fails, check local storage as fallback
        NyLogger.error('API Error: $e. Checking local storage...');

        List<String>? enrolledCourseIds =
            await NyStorage.read('enrolled_course_ids');

        if (enrolledCourseIds != null && enrolledCourseIds.isNotEmpty) {
          // Fetch all courses to find the enrolled ones
          List<dynamic> allCoursesData = await courseApiService.getAllCourses();
          List<Course> allCourses =
              allCoursesData.map((data) => Course.fromJson(data)).toList();

          // Filter to get only enrolled courses
          _enrolledCourses = allCourses
              .where((course) => enrolledCourseIds.contains(course.id))
              .toList();
          _hasCourses = _enrolledCourses.isNotEmpty;
        } else {
          _enrolledCourses = [];
          _hasCourses = false;
        }
      }

      // Load progress data for courses
      await _loadCourseProgress();
    } catch (e) {
      NyLogger.error('Failed to fetch enrolled courses: $e');

      showToast(
          title: trans("Error"),
          description: trans("Failed to load your courses"),
          icon: Icons.error_outline,
          style: ToastNotificationStyleType.danger);

      // Reset state on error
      setState(() {
        _enrolledCourses = [];
        _hasCourses = false;
      });
    } finally {
      setLoading(false, name: 'fetch_enrolled_courses');
    }
  }

  void _onGetStartedPressed() async {
    // Navigate to search tab
    routeTo(BaseNavigationHub.path, tabIndex: 1);
  }

  void _onStartCourse(Course course) {
    // Navigate to purchased course detail page
    routeTo(PurchasedCourseDetailPage.path, data: {
      'course': course,
    });
  }

  Future<void> _onRefresh() async {
    // Using Nylo's lockRelease to prevent multiple refreshes
    await lockRelease('refresh_courses', perform: () async {
      await _fetchEnrolledCourses(refresh: true);

      // Show success toast
      showToastSuccess(description: trans("Courses refreshed successfully"));
    });
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
                color: Colors.grey.withAlpha(77),
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
              trans("My Courses"),
              style: TextStyle(
                color: Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            actions: [
              // Refresh button
              if (_isAuthenticated)
                IconButton(
                  icon: Icon(Icons.refresh, color: Colors.black87),
                  onPressed: _onRefresh,
                ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          child: afterLoad(
            loadingKey: 'fetch_enrolled_courses',
            child: () => Column(
              children: [
                // Main Content
                Expanded(
                  child: _isAuthenticated
                      ? (_hasCourses ? _buildCoursesList() : _buildEmptyState())
                      : _buildLoginPrompt(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Spacer(flex: 1),

          // Image
          Image.asset(
            "bro.png",
            width: 150,
            height: 150,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                width: 150,
                height: 150,
                child: Icon(
                  Icons.school,
                  size: 80,
                  color: Colors.grey.shade400,
                ),
              );
            },
          ).localAsset(),

          SizedBox(height: 24),

          // Title
          Text(
            trans("Start your journey to becoming a master"),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
            textAlign: TextAlign.center,
          ),

          SizedBox(height: 8),

          // Subtitle
          Text(
            trans("Get your first course now!"),
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),

          SizedBox(height: 20),

          // Get Started Button
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: ElevatedButton(
              onPressed: _onGetStartedPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                padding: EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(
                trans("Get Started"),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          Spacer(flex: 1),
        ],
      ),
    );
  }

  Widget _buildLoginPrompt() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Spacer(flex: 1),

          // Image
          Image.asset(
            "bro.png",
            width: 150,
            height: 150,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                width: 150,
                height: 150,
                child: Icon(
                  Icons.lock,
                  size: 80,
                  color: Colors.grey.shade400,
                ),
              );
            },
          ).localAsset(),

          SizedBox(height: 24),

          // Title
          Text(
            trans("Login to access your courses"),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
            textAlign: TextAlign.center,
          ),

          SizedBox(height: 8),

          // Subtitle
          Text(
            trans("Sign in to view your enrolled courses"),
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),

          SizedBox(height: 20),

          // Login Button
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: ElevatedButton(
              onPressed: () {
                routeTo('/login');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(
                trans("Login"),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          SizedBox(height: 16),

          // Browse Courses Button
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton(
              onPressed: _onGetStartedPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black87,
                side: BorderSide(color: Colors.grey.shade300),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(
                trans("Browse Courses"),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          Spacer(flex: 1),
        ],
      ),
    );
  }

  Widget _buildCoursesList() {
    // If there are no courses, show empty state
    if (_enrolledCourses.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.separated(
      padding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      itemCount: _enrolledCourses.length,
      separatorBuilder: (context, index) => SizedBox(height: 16),
      itemBuilder: (context, index) {
        final course = _enrolledCourses[index];
        return _buildCourseItem(course);
      },
    );
  }

  Widget _buildCourseItem(Course course) {
    // Get progress from stored data
    double progressPercentage = _courseProgress[course.id.toString()] ?? 0.0;
    int videoCount =
        _courseVideoCount[course.id.toString()] ?? ((course.id ?? 1) % 10) + 5;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Course Image and Info
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Course Image
              ClipRRect(
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                ),
                child: Image.network(
                  course.image,
                  width: 100,
                  height: 100,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 100,
                      height: 100,
                      color: Colors.grey.shade300,
                      child: Icon(
                        Icons.image_not_supported,
                        color: Colors.grey.shade700,
                      ),
                    );
                  },
                ),
              ),

              // Course Info
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Course Title
                      Text(
                        course.title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),

                      SizedBox(height: 4),

                      // Course Subtitle
                      Text(
                        course.smallDesc,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),

                      SizedBox(height: 8),

                      // Progress indicator
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Progress text
                          Text(
                            "${(progressPercentage * 100).toInt()}% ${trans("Complete")}",
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),

                          SizedBox(height: 4),

                          // Progress bar
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: progressPercentage,
                              backgroundColor: Colors.grey.shade200,
                              color: Colors.amber,
                              minHeight: 5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Action Buttons
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Video Stats
                Row(
                  children: [
                    Icon(Icons.video_library,
                        size: 16, color: Colors.grey.shade700),
                    SizedBox(width: 4),
                    Text(
                      "$videoCount ${trans("videos")}",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),

                // Continue Button
                ElevatedButton(
                  onPressed: () => _onStartCourse(course),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: Text(
                    progressPercentage > 0
                        ? trans("Continue")
                        : trans("Begin Course"),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Skeleton layout for loading state
  Widget _buildSkeletonLayout() {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(56),
        child: Container(
          color: Colors.white,
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView.separated(
          padding: EdgeInsets.all(16),
          itemCount: 5,
          separatorBuilder: (context, index) => SizedBox(height: 16),
          itemBuilder: (context, index) {
            return Container(
              height: 140,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Container(
                    width: 100,
                    color: Colors.grey.shade300,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Container(
                            height: 16,
                            width: double.infinity,
                            color: Colors.grey.shade300,
                          ),
                          Container(
                            height: 12,
                            width: 200,
                            color: Colors.grey.shade300,
                          ),
                          Container(
                            height: 8,
                            width: 120,
                            color: Colors.grey.shade300,
                          ),
                          Container(
                            height: 30,
                            width: 100,
                            color: Colors.grey.shade300,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
