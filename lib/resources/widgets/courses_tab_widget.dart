import 'package:flutter/material.dart';
import 'package:flutter_app/resources/pages/base_navigation_hub.dart';
import 'package:flutter_app/resources/pages/purchased_course_detail_page.dart';
import 'package:nylo_framework/nylo_framework.dart';

import '../../app/models/course.dart';
import '../../app/networking/course_api_service.dart';

class CoursesTab extends StatefulWidget {
  const CoursesTab({super.key});

  static String state = '/courses_tab';

  @override
  createState() => _CoursesTabState();
}

class _CoursesTabState extends NyState<CoursesTab> {
  List<Course> _enrolledCourses = [];
  bool _hasCourses = false;
  bool _isAuthenticated = false;

  // Store curriculum data to avoid repeated API calls
  Map<String, List<dynamic>> _curriculumCache = {};
  Map<String, List<dynamic>> _objectivesCache = {};
  Map<String, List<dynamic>> _requirementsCache = {};

  Map<String, double> _courseProgress = {};
  Map<String, int> _courseVideoCount = {};

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

        _isAuthenticated = await Auth.isAuthenticated();
        await _fetchEnrolledCourses();
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
        String key = 'course_progress_${course.id}';
        var savedProgress = await NyStorage.read(key);

        if (savedProgress != null) {
          var completedLessons = (savedProgress is Map &&
                  savedProgress.containsKey('completedLessons'))
              ? savedProgress['completedLessons']
              : {};

          var completedCount =
              completedLessons.values.where((v) => v == true).length;

          // Get video count from cache first, then API if needed
          int totalVideos = await _getCourseVideoCount(course.id);
          double progress =
              totalVideos > 0 ? completedCount / totalVideos : 0.0;

          setState(() {
            _courseProgress[course.id.toString()] = progress;
            _courseVideoCount[course.id.toString()] = totalVideos;
          });
        } else {
          int totalVideos = await _getCourseVideoCount(course.id);
          setState(() {
            _courseProgress[course.id.toString()] = 0.0;
            _courseVideoCount[course.id.toString()] = totalVideos;
          });
        }
      } catch (e) {
        NyLogger.error('Failed to load progress for course ${course.id}: $e');
        setState(() {
          _courseProgress[course.id.toString()] = 0.0;
          _courseVideoCount[course.id.toString()] = 0;
        });
      }
    }
  }

  Future<int> _getCourseVideoCount(int courseId) async {
    String cacheKey = courseId.toString();

    // Check cache first
    if (_curriculumCache.containsKey(cacheKey)) {
      return _curriculumCache[cacheKey]!.length;
    }

    // Fetch and cache curriculum
    try {
      var courseApiService = CourseApiService();
      List<dynamic> curriculum =
          await courseApiService.getCourseCurriculum(courseId);

      // Cache for future use
      _curriculumCache[cacheKey] = curriculum;

      return curriculum.length;
    } catch (e) {
      NyLogger.error('Error fetching curriculum for course $courseId: $e');
      return 0;
    }
  }

  Future<void> _fetchEnrolledCourses({bool refresh = false}) async {
    setLoading(true, name: 'fetch_enrolled_courses');

    try {
      if (!_isAuthenticated) {
        setState(() {
          _enrolledCourses = [];
          _hasCourses = false;
        });
        return;
      }

      var courseApiService = CourseApiService();

      try {
        List<dynamic> enrolledCoursesData =
            await courseApiService.getEnrolledCourses();

        if (enrolledCoursesData.isNotEmpty) {
          _enrolledCourses = enrolledCoursesData
              .map((data) => Course.fromJson(data['course']))
              .toList();
          _hasCourses = _enrolledCourses.isNotEmpty;

          // Preload curriculum data in background for better UX
          if (!refresh) {
            _preloadCourseData();
          }
        } else {
          _enrolledCourses = [];
          _hasCourses = false;
        }
      } catch (e) {
        NyLogger.error('API Error: $e. Checking local storage...');

        List<String>? enrolledCourseIds =
            await NyStorage.read('enrolled_course_ids');

        if (enrolledCourseIds != null && enrolledCourseIds.isNotEmpty) {
          List<dynamic> allCoursesData = await courseApiService.getAllCourses();
          List<Course> allCourses =
              allCoursesData.map((data) => Course.fromJson(data)).toList();

          _enrolledCourses = allCourses
              .where((course) => enrolledCourseIds.contains(course.id))
              .toList();
          _hasCourses = _enrolledCourses.isNotEmpty;
        } else {
          _enrolledCourses = [];
          _hasCourses = false;
        }
      }

      await _loadCourseProgress();
    } catch (e) {
      NyLogger.error('Failed to fetch enrolled courses: $e');

      showToast(
          title: trans("Error"),
          description: trans("Failed to load your courses"),
          icon: Icons.error_outline,
          style: ToastNotificationStyleType.danger);

      setState(() {
        _enrolledCourses = [];
        _hasCourses = false;
      });
    } finally {
      setLoading(false, name: 'fetch_enrolled_courses');
    }
  }

  // Preload course data in background for better performance
  Future<void> _preloadCourseData() async {
    final courseApiService = CourseApiService();

    for (var course in _enrolledCourses) {
      String cacheKey = course.id.toString();

      // Skip if already cached
      if (_curriculumCache.containsKey(cacheKey)) continue;

      // Preload curriculum, objectives, and requirements in parallel
      Future.wait([
        courseApiService.getCourseCurriculum(course.id).then((curriculum) {
          _curriculumCache[cacheKey] = curriculum;
        }).catchError((e) {
          NyLogger.error('Error preloading curriculum for ${course.id}: $e');
        }),
        courseApiService.getCourseObjectives(course.id).then((objectives) {
          _objectivesCache[cacheKey] = objectives;
        }).catchError((e) {
          NyLogger.error('Error preloading objectives for ${course.id}: $e');
        }),
        courseApiService.getCourseRequirements(course.id).then((requirements) {
          _requirementsCache[cacheKey] = requirements;
        }).catchError((e) {
          NyLogger.error('Error preloading requirements for ${course.id}: $e');
        }),
      ]);
    }
  }

  void _onGetStartedPressed() async {
    routeTo(BaseNavigationHub.path, tabIndex: 1);
  }

  void _onStartCourse(Course course) {
    String cacheKey = course.id.toString();

    // Pass cached data to avoid API calls
    Map<String, dynamic> courseData = {
      'course': course,
    };

    // Add cached curriculum if available
    if (_curriculumCache.containsKey(cacheKey)) {
      courseData['curriculum'] = _curriculumCache[cacheKey];
    }

    // Add cached objectives if available
    if (_objectivesCache.containsKey(cacheKey)) {
      courseData['objectives'] = _objectivesCache[cacheKey];
    }

    // Add cached requirements if available
    if (_requirementsCache.containsKey(cacheKey)) {
      courseData['requirements'] = _requirementsCache[cacheKey];
    }

    routeTo(PurchasedCourseDetailPage.path, data: courseData);
  }

  Future<void> _onRefresh() async {
    await lockRelease('refresh_courses', perform: () async {
      // Clear caches on refresh
      _curriculumCache.clear();
      _objectivesCache.clear();
      _requirementsCache.clear();

      await _fetchEnrolledCourses(refresh: true);
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
          Text(
            trans("Get your first course now!"),
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 20),
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
          Text(
            trans("Sign in to view your enrolled courses"),
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 20),
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
    double progressPercentage = _courseProgress[course.id.toString()] ?? 0.0;
    int videoCount =
        _courseVideoCount[course.id.toString()] ?? ((course.id) % 10) + 5;

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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "${(progressPercentage * 100).toInt()}% ${trans("Complete")}",
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(height: 4),
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
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
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
