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

  final CourseApiService _courseApiService = CourseApiService();
  final PurchaseApiService _purchaseApiService = PurchaseApiService();
  final VideoService _videoService = VideoService();

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

          // Load real data from API in parallel for better performance
          await Future.wait([
            _loadCourseCurriculum(courseId),
            _loadCourseObjectives(courseId),
            _loadCourseRequirements(courseId),
            _checkWishlistStatus(),
            _checkEnrollmentStatus(),
          ]);
        } catch (e) {
          NyLogger.error('Error initializing course detail: $e');
          showToastDanger(description: "Failed to load course details: $e");
        } finally {
          // Complete all loading indicators
          setLoading(false, name: 'course_detail');
          setLoading(false, name: 'curriculum');
          setLoading(false, name: 'objectives');
          setLoading(false, name: 'requirements');
        }
      };

  Future<void> _loadCourseCurriculum(int courseId) async {
    try {
      curriculumItems = await _courseApiService.getCourseCurriculum(courseId);
      // Sort by order field
      curriculumItems.sort((a, b) => a['order'].compareTo(b['order']));
    } catch (e) {
      NyLogger.error('Error loading curriculum: $e');
      // Set empty list on error
      curriculumItems = [];
    }
  }

  Future<void> _loadCourseObjectives(int courseId) async {
    try {
      objectives = await _courseApiService.getCourseObjectives(courseId);
    } catch (e) {
      NyLogger.error('Error loading objectives: $e');
      // Set empty list on error
      objectives = [];
    }
  }

  Future<void> _loadCourseRequirements(int courseId) async {
    try {
      requirements = await _courseApiService.getCourseRequirements(courseId);
    } catch (e) {
      NyLogger.error('Error loading requirements: $e');
      // Set empty list on error
      requirements = [];
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
      NyLogger.error('Error checking wishlist status: $e');
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
      NyLogger.error('Error checking enrollment status: $e');
    }
  }

  Future<void> _toggleWishlist() async {
    if (courseDetail == null) return;

    // Check authentication
    bool isAuthenticated = await Auth.isAuthenticated();
    if (!isAuthenticated) {
      confirmAction(() {
        routeTo('/login');
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
      NyLogger.error('Error toggling wishlist: $e');
      showToastDanger(description: trans("Failed to update wishlist"));
    } finally {
      setState(() {
        _isLoadingWishlist = false;
      });
    }
  }

  Future<void> _handleEnrollment() async {
    if (courseDetail == null) return;

    // If already enrolled, just show curriculum
    if (_isEnrolled) {
      routeTo(CourseCurriculumPage.path, data: {'course': courseDetail});
      return;
    }

    // Check authentication
    bool isAuthenticated = await Auth.isAuthenticated();
    if (!isAuthenticated) {
      confirmAction(() {
        routeTo('/login');
      },
          title: trans("You need to login to enroll in courses."),
          confirmText: trans("Login"),
          dismissText: trans("Cancel"));
      return;
    }

    // Check if user has an active subscription
    try {
      bool hasActiveSubscription =
          await _purchaseApiService.hasActiveSubscription();

      if (hasActiveSubscription) {
        // User already has subscription, directly enroll
        await _courseApiService.enrollInCourse(courseDetail!.id);
        showToastSuccess(description: trans("Successfully enrolled in course"));
        setState(() {
          _isEnrolled = true;
        });

        // Notify other tabs
        updateState('/search_tab', data: "refresh_courses");
        updateState('/home_tab', data: "refresh_enrollments");

        // Navigate to curriculum
        routeTo(CourseCurriculumPage.path, data: {'course': courseDetail});
      } else {
        // User needs a subscription, navigate to subscription page
        routeTo(EnrollmentPlanPage.path, data: {'course': courseDetail});
      }
    } catch (e) {
      NyLogger.error('Error handling enrollment: $e');
      showToastDanger(
          description: trans("An error occurred, please try again"));
    }
  }

  void _promptVideoDownload(int index) async {
    // Check if user is authenticated
    bool isAuthenticated = await Auth.isAuthenticated();
    if (!isAuthenticated) {
      confirmAction(() {
        routeTo('/login');
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
          // description: trans("You need to enroll in this course to watch videos"),
          confirmText: trans("Enroll Now"),
          dismissText: trans("Cancel"));
      return;
    }

    // Prompt to view curriculum page where videos can be downloaded
    confirmAction(() {
      routeTo(CourseCurriculumPage.path,
          data: {'course': courseDetail, 'curriculum': curriculumItems});
    },
        title: trans("Download Required"),
        // description: trans("You need to download the video before watching it"),
        confirmText: trans("Go to Curriculum"),
        dismissText: trans("Cancel"));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      // Use AppBar for the static back button
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false, // Don't show default back button
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => pop(),
        ),
        title: SizedBox(), // Empty title
      ),
      body: afterLoad(
        loadingKey: 'course_detail',
        child: () => SingleChildScrollView(
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

          // Enroll Button
          Container(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _handleEnrollment,
              child: Text(
                _isEnrolled ? trans('View Course') : trans('Enroll Now'),
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
              "${curriculumItems.length} ${trans('videos')} • - hours - minutes total length",
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

            // Always show "See all Videos" button regardless of item count
            GestureDetector(
              onTap: () {
                routeTo(CourseCurriculumPage.path, data: {
                  'course': courseDetail,
                  'curriculum': curriculumItems
                });
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
              onPressed: _handleEnrollment,
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
