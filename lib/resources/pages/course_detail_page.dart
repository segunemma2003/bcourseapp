import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_app/app/models/course.dart';
import 'package:flutter_app/resources/pages/enrollment_plan_page.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../app/models/curriculum.dart';
import '../../app/models/objectives.dart';
import '../../app/models/requirements.dart';
import '../../app/models/wishlist.dart';
import '../../app/networking/course_api_service.dart';
import '../../app/networking/purchase_api_service.dart';
import '../../app/services/video_service.dart';
import 'course_curriculum_page.dart';
import 'signin_page.dart';

class CourseDetailPage extends NyStatefulWidget {
  static RouteView path = ("/course-detail", (_) => CourseDetailPage());

  CourseDetailPage({super.key}) : super(child: () => _CourseDetailPageState());
}

class _CourseDetailPageState extends NyPage<CourseDetailPage> {
  Course? courseDetail;
  List<dynamic> curriculumItems = [];
  List<dynamic> objectives = [];
  List<dynamic> requirements = [];
  bool _isInWishlist = false;
  bool _isEnrolled = false;
  bool _isLoadingWishlist = false;
  bool _isInitializing = true; // Added to track initialization state

  // Total duration calculation
  String _totalDuration = "- minutes";

  // Download tracking
  StreamSubscription? _downloadProgressSubscription;

  final CourseApiService _courseApiService = CourseApiService();
  final PurchaseApiService _purchaseApiService = PurchaseApiService();
  final VideoService _videoService = VideoService();

  // Scroll controller
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    // Listen for download progress updates
    // _subscribeToDownloadProgress();
  }

  // Subscribe to download progress updates
  // void _subscribeToDownloadProgress() {
  //   _downloadProgressSubscription =
  //       _videoService.progressStream.listen((update) {
  //     // CRITICAL: Always check if widget is still mounted before calling setState
  //     if (!mounted) return;

  //     setState(() {
  //       // The update happens in VideoService, we just need to refresh the UI
  //     });
  //   });
  // }

  @override
  void dispose() {
    // Cancel download progress subscription
    if (_downloadProgressSubscription != null) {
      _downloadProgressSubscription!.cancel();
      _downloadProgressSubscription = null;
    }

    // Dispose of scroll controller
    _scrollController.dispose();

    super.dispose();
  }

  @override
  boot() async {
    // Initialize services
  }

  @override
  LoadingStyle get loadingStyle => LoadingStyle.skeletonizer();

  @override
  get init => () async {
        // Start multiple loading indicators
        setLoading(true, name: 'course_detail');
        setLoading(true, name: 'curriculum');
        setLoading(true, name: 'objectives');
        setLoading(true, name: 'requirements');

        try {
          // Get course data from route arguments
          Map<String, dynamic> data = widget.data();
          if (data.containsKey('course') && data['course'] != null) {
            courseDetail = data['course'];
          } else {
            // Handle case when course data is missing
            showToastDanger(description: "Course information is missing");
            pop();
            return;
          }

          // Convert course ID to int for API calls
          int courseId = courseDetail!.id;

          // Load each data type separately for better error handling
          // We use Future.microtask to allow the UI to update between each task

          // Load curriculum items first - most important
          await _loadCourseCurriculum(courseId).catchError((e) {
            print('Error loading curriculum: $e');
            // Set empty list on error
            curriculumItems = [];
          });

          // Signal that the curriculum is loaded
          if (mounted) {
            setLoading(false, name: 'curriculum');
            // Calculate total duration once curriculum is loaded
            _calculateTotalDuration();
          }

          // Load objectives next
          await _loadCourseObjectives(courseId).catchError((e) {
            print('Error loading objectives: $e');
            objectives = [];
          });

          if (mounted) {
            setLoading(false, name: 'objectives');
          }

          // Load requirements next
          await _loadCourseRequirements(courseId).catchError((e) {
            print('Error loading requirements: $e');
            requirements = [];
          });

          if (mounted) {
            setLoading(false, name: 'requirements');
          }

          // Load user-specific data in parallel
          await Future.wait([
            _checkWishlistStatus(),
            _checkEnrollmentStatus(),
          ]).catchError((e) {
            print('Error loading user data: $e');
          });

          // Mark initialization as complete
          _isInitializing = false;

          // Complete all loading indicators
          if (mounted) {
            setLoading(false, name: 'course_detail');
          }
        } catch (e) {
          print('Error initializing course detail: $e');
          showToastDanger(description: "Failed to load course details");

          // Complete loading indicators even on error
          if (mounted) {
            setLoading(false, name: 'course_detail');
            setLoading(false, name: 'curriculum');
            setLoading(false, name: 'objectives');
            setLoading(false, name: 'requirements');
          }
        }
      };

  // Calculate total duration from curriculum items
  void _calculateTotalDuration() {
    try {
      int totalSeconds = 0;
      for (var item in curriculumItems) {
        if (item.containsKey('duration') && item['duration'] != null) {
          String duration = item['duration'].toString();
          List<String> parts = duration.split(':');
          if (parts.length == 2) {
            try {
              int minutes = int.parse(parts[0]);
              int seconds = int.parse(parts[1]);
              totalSeconds += (minutes * 60) + seconds;
            } catch (e) {
              // Skip invalid durations
              print('Error parsing duration: $e');
            }
          }
        }
      }

      // Format total duration
      int hours = totalSeconds ~/ 3600;
      int minutes = (totalSeconds % 3600) ~/ 60;

      setState(() {
        _totalDuration =
            hours > 0 ? "$hours hours $minutes minutes" : "$minutes minutes";
      });
    } catch (e) {
      print('Error calculating total duration: $e');
      setState(() {
        _totalDuration = "- minutes";
      });
    }
  }

  Future<void> _loadCourseCurriculum(int courseId) async {
    try {
      curriculumItems = await _courseApiService.getCourseCurriculum(courseId);
      // Sort by order field
      curriculumItems.sort((a, b) => a['order'].compareTo(b['order']));
    } catch (e) {
      print('Error loading curriculum: $e');
      // Set empty list on error
      curriculumItems = [];
      rethrow; // Rethrow to indicate this operation failed
    }
  }

  Future<void> _loadCourseObjectives(int courseId) async {
    try {
      objectives = await _courseApiService.getCourseObjectives(courseId);
    } catch (e) {
      print('Error loading objectives: $e');
      // Set empty list on error
      objectives = [];
      rethrow; // Rethrow to indicate this operation failed
    }
  }

  Future<void> _loadCourseRequirements(int courseId) async {
    try {
      requirements = await _courseApiService.getCourseRequirements(courseId);
    } catch (e) {
      print('Error loading requirements: $e');
      // Set empty list on error
      requirements = [];
      rethrow; // Rethrow to indicate this operation failed
    }
  }

  Future<void> _checkWishlistStatus() async {
    try {
      // Only check if authenticated
      if (await Auth.isAuthenticated()) {
        final wishlistData = await _courseApiService.getWishlist();
        final wishlistItems =
            wishlistData.map((data) => Wishlist.fromJson(data)).toList();
        setState(() {
          _isInWishlist = wishlistItems.any((item) =>
              item.courseId.toString() == courseDetail!.id.toString());
        });
      }
    } catch (e) {
      print('Error checking wishlist status: $e');
      rethrow; // Rethrow to indicate this operation failed
    }
  }

  Future<void> _checkEnrollmentStatus() async {
    try {
      // Only check if authenticated
      if (await Auth.isAuthenticated()) {
        final enrollments = await _courseApiService.getEnrolledCourses();
        setState(() {
          _isEnrolled = enrollments.any((item) =>
              item['course'] != null &&
              item['course']['id'].toString() == courseDetail!.id.toString());
        });
      }
    } catch (e) {
      print('Error checking enrollment status: $e');
      rethrow; // Rethrow to indicate this operation failed
    }
  }

  Future<void> _toggleWishlist() async {
    if (courseDetail == null) return;

    // Check authentication
    bool isAuthenticated = await Auth.isAuthenticated();
    if (!isAuthenticated) {
      confirmAction(() {
        routeTo(SigninPage.path);
      },
          title: trans("You need to login to save courses to your wishlist."),
          confirmText: trans("Login"),
          dismissText: trans("Cancel"));
      return;
    }

    setState(() {
      _isLoadingWishlist = true;
    });

    try {
      if (_isInWishlist) {
        // Find wishlist item id first
        final wishlistData = await _courseApiService.getWishlist();
        final wishlistItems =
            wishlistData.map((data) => Wishlist.fromJson(data)).toList();

        // Instead of using firstWhere with orElse, use where and check if the result is not empty
        final matchingItems = wishlistItems
            .where(
              (item) => item.courseId.toString() == courseDetail!.id.toString(),
            )
            .toList();

        if (matchingItems.isNotEmpty) {
          // Remove from wishlist - use the first matching item
          await _courseApiService.removeFromWishlist(matchingItems.first.id);
          setState(() {
            _isInWishlist = false;
          });
          showToastInfo(description: trans("Course removed from wishlist"));
        }
      } else {
        // Add to wishlist
        await _courseApiService.addToWishlist(courseDetail!.id);
        setState(() {
          _isInWishlist = true;
        });
        showToastSuccess(description: trans("Course added to wishlist"));
      }

      // Notify other tabs about the change
      updateState('/search_tab', data: {
        "update_wishlist_status": {
          "course_id": courseDetail!.id,
          "is_in_wishlist": _isInWishlist
        }
      });
      updateState('/wishlist_tab', data: "refresh_wishlist");
    } catch (e) {
      print('Error toggling wishlist: $e');
      showToastDanger(description: trans("Failed to update wishlist"));
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingWishlist = false;
        });
      }
    }
  }

  Future<void> _handleEnrollment() async {
    if (courseDetail == null) return;

    // If already enrolled, just show curriculum
    if (_isEnrolled) {
      _navigateToCurriculum();
      return;
    }

    // Check authentication
    bool isAuthenticated = await Auth.isAuthenticated();
    if (!isAuthenticated) {
      confirmAction(() {
        routeTo(SigninPage.path);
      },
          title: trans("You need to login to enroll in courses."),
          confirmText: trans("Login"),
          dismissText: trans("Cancel"));
      return;
    }

    // Show loading indicator
    showLoadingDialog(trans("Checking subscription..."));

    // Check if user has an active subscription
    try {
      bool hasActiveSubscription =
          await _purchaseApiService.hasActiveSubscription();

      // Hide loading dialog
      Navigator.pop(context);

      if (hasActiveSubscription) {
        // Show enrolling progress
        showLoadingDialog(trans("Enrolling..."));

        // User already has subscription, directly enroll
        await _courseApiService.enrollInCourse(courseDetail!.id);

        // Hide loading dialog
        if (mounted) Navigator.pop(context);

        showToastSuccess(description: trans("Successfully enrolled in course"));
        setState(() {
          _isEnrolled = true;
        });

        // Notify other tabs
        updateState('/search_tab', data: "refresh_courses");
        updateState('/home_tab', data: "refresh_enrollments");

        // Navigate to curriculum
        _navigateToCurriculum();
      } else {
        // User needs a subscription, navigate to subscription page
        routeTo(EnrollmentPlanPage.path, data: {'course': courseDetail});
      }
    } catch (e) {
      // Hide loading dialog if still showing
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      print('Error handling enrollment: $e');
      showToastDanger(
          description: trans("An error occurred, please try again"));
    }
  }

  // Helper method to navigate to curriculum page
  void _navigateToCurriculum() {
    // Use Future.microtask to prevent UI blocking
    Future.microtask(() {
      routeTo(CourseCurriculumPage.path,
          data: {'course': courseDetail, 'curriculum': curriculumItems});
    });
  }

  // Show loading dialog
  void showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text(message),
            ],
          ),
        );
      },
    );
  }

  void _promptVideoDownload(int index) async {
    // Check if user is authenticated
    bool isAuthenticated = await Auth.isAuthenticated();
    if (!isAuthenticated) {
      confirmAction(() {
        routeTo(SigninPage.path);
      },
          title: trans("You need to login to watch videos"),
          confirmText: trans("Login"),
          dismissText: trans("Cancel"));
      return;
    }

    // Check if enrolled
    if (!_isEnrolled) {
      confirmAction(() {
        _handleEnrollment();
      },
          title: trans("Enrollment Required"),
          // message:
          //     trans("You need to enroll in this course to access the videos."),
          confirmText: trans("Enroll Now"),
          dismissText: trans("Cancel"));
      return;
    }

    // If enrolled, navigate to curriculum page
    _navigateToCurriculum();
  }

  @override
  Widget view(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false, // Don't show default back button
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => pop(),
        ),
        title: SizedBox(), // Empty title
        // Add a refresh button to the app bar
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.black),
            onPressed: _isInitializing
                ? null // Disable when initializing
                : () {
                    // Refresh the page data
                    setLoading(true, name: 'course_detail');
                    init();
                  },
          ),
        ],
      ),
      body: afterLoad(
        loadingKey: 'course_detail',
        child: () => RefreshIndicator(
          onRefresh: () async {
            // Pull-to-refresh functionality
            setLoading(true, name: 'course_detail');
            await init();
          },
          child: SingleChildScrollView(
            controller: _scrollController,
            physics: AlwaysScrollableScrollPhysics(), // Always scrollable
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hero Image with CachedNetworkImage for better loading
                _buildCourseImage(),

                // Course Title and Subtitle
                _buildCourseInfo(),

                // Objectives/What you'll achieve
                _buildAchievementsSection(),

                // Course Curriculum - with white background and box shadow
                _buildCurriculumSection(),

                // Requirements - with white background and box shadow
                _buildRequirementsSection(),

                // Bottom action button
                _buildBottomAction(),

                // Add some bottom padding for safety
                SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCourseImage() {
    return Container(
      height: 200,
      width: double.infinity,
      child: CachedNetworkImage(
        imageUrl: courseDetail?.image ?? '',
        height: 200,
        width: double.infinity,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          height: 200,
          width: double.infinity,
          color: Colors.grey[300],
          child: Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ),
        errorWidget: (context, url, error) => Container(
          height: 200,
          width: double.infinity,
          color: Colors.grey[300],
          child:
              Icon(Icons.image_not_supported, color: Colors.white70, size: 50),
        ),
      ),
    );
  }

  Widget _buildCourseInfo() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            courseDetail?.title ?? '',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            courseDetail?.smallDesc ?? '',
            style: TextStyle(
              fontSize: 12,
              color: Colors.black,
            ),
          ),
          SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.people, size: 18, color: Colors.grey),
              SizedBox(width: 4),
              Text(
                "${courseDetail?.enrolledStudents ?? 0}",
                style: TextStyle(color: Colors.black, fontSize: 10),
              ),
            ],
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.calendar_today,
                size: 18,
                color: Colors.black,
              ),
              SizedBox(width: 4),
              Text(
                'Updated ${courseDetail?.dateUploaded ?? ''}',
                style: TextStyle(color: Colors.black, fontSize: 10),
              ),
            ],
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.language,
                size: 16,
                color: Colors.black,
              ),
              SizedBox(width: 4),
              Text(
                courseDetail?.location ?? '',
                style: TextStyle(color: Colors.black, fontSize: 10),
              ),
            ],
          ),
          SizedBox(height: 24),

          // Only show Enroll Button if not enrolled
          if (!_isEnrolled)
            Container(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _handleEnrollment,
                child: Text(
                  trans('Enroll Now'),
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFFEFE458), // Yellow
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
              ),
            )
          else
            Container(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _navigateToCurriculum,
                child: Text(
                  trans('View Course'),
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFFEFE458), // Yellow
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
              ),
            ),
          SizedBox(height: 12),

          // Wishlist Button
          Container(
            width: double.infinity,
            height: 50,
            child: OutlinedButton(
              onPressed: _isLoadingWishlist ? null : _toggleWishlist,
              child: _isLoadingWishlist
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.black54),
                      ))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isInWishlist
                              ? Icons.favorite
                              : Icons.favorite_border,
                          color: _isInWishlist ? Colors.red : Colors.black,
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Text(
                          _isInWishlist
                              ? trans('Remove from Wishlist')
                              : trans('Add to Wishlist'),
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.black),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAchievementsSection() {
    return afterLoad(
      loadingKey: 'objectives',
      child: () => Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              trans('What you\'ll achieve after the course'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 16),
            // Build achievement items from API data
            if (objectives.isEmpty)
              Text(
                trans('No objectives available for this course'),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              )
            else
              ...objectives
                  .map((objective) =>
                      _buildAchievementItem(objective['description'] ?? ''))
                  .toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildCurriculumSection() {
    return afterLoad(
      loadingKey: 'curriculum',
      child: () => Container(
        margin: EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.2),
              spreadRadius: 1,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              trans('Course Curriculum'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              "${curriculumItems.length} ${trans('videos')} • $_totalDuration total length",
              style: TextStyle(
                fontSize: 10,
                color: Colors.black,
              ),
            ),
            SizedBox(height: 10),
            // Check if curriculum is available
            if (curriculumItems.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Center(
                  child: Text(
                    trans('No curriculum items available'),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
              )
            else
              // Always show only first 5 items
              ListView.builder(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                itemCount:
                    curriculumItems.length > 5 ? 5 : curriculumItems.length,
                itemBuilder: (context, index) {
                  final item = curriculumItems[index];
                  return _buildCurriculumItem(
                    index + 1, // Convert to 1-based index for display
                    item['title'] ?? 'Class Introduction Video',
                    item['duration'] ?? '5:05',
                    videoUrl: item['video_url'] ?? '',
                    onTap: () => _promptVideoDownload(index),
                  );
                },
              ),
            SizedBox(height: 10),

            // Only show "See all Videos" button if user is enrolled or if there are more than 5 videos
            if (_isEnrolled || curriculumItems.length > 5)
              GestureDetector(
                onTap: () {
                  _navigateToCurriculum();
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      trans('See all Videos'),
                      style: TextStyle(
                        color: Color(0xFFE5A200), // Yellow color
                        fontSize: 14,
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward,
                      size: 16,
                      color: Color(0xFFE5A200), // Matching icon color
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequirementsSection() {
    return afterLoad(
      loadingKey: 'requirements',
      child: () => Container(
        margin: EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.2),
              spreadRadius: 1,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              trans('Requirements'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 16),
            // Check if requirements are available
            if (requirements.isEmpty)
              Text(
                trans('No requirements specified for this course'),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              )
            else
              ...requirements
                  .map((requirement) =>
                      _buildRequirementItem(requirement['description'] ?? ''))
                  .toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomAction() {
    return Container(
      padding: EdgeInsets.all(16),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            width: 150,
            height: 50,
            child: ElevatedButton(
              onPressed:
                  _isEnrolled ? _navigateToCurriculum : _handleEnrollment,
              child: Text(
                _isEnrolled ? trans('View Course') : trans('Enroll Now'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFFEFE458), // Yellow
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAchievementItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: EdgeInsets.only(top: 4),
            child: Icon(
              Icons.check,
              color: Colors.amber,
              size: 20,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurriculumItem(int index, String title, String duration,
      {String? videoUrl, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          // Simple text number without background
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            child: Text(
              "$index",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Colors.black87,
              ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
                Text(
                  'Video · ${duration}',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onTap,
            child: Icon(
              Icons.play_circle_outline,
              color: Colors.amber,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequirementItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: EdgeInsets.only(top: 6),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: Colors.black,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[800],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
