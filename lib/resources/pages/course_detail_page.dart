import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_app/app/models/course.dart';
import 'package:flutter_app/resources/pages/enrollment_plan_page.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'package:cached_network_image/cached_network_image.dart';

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
  bool _isInitializing = true;
  bool _hasValidSubscription = false;
  bool _isAuthenticated = false;
  bool _isLifetimeSubscription = false;
  DateTime? _subscriptionExpiryDate;
  String _subscriptionStatus = 'not_enrolled';
  String _subscriptionPlanName = 'Unknown';
  List<String> _enrolledCourseIds = [];

  String _totalDuration = "- minutes";
  bool _isChecking = false;

  StreamSubscription? _downloadProgressSubscription;

  final CourseApiService _courseApiService = CourseApiService();
  final PurchaseApiService _purchaseApiService = PurchaseApiService();
  final VideoService _videoService = VideoService();
  final ScrollController _scrollController = ScrollController();

  bool _listsEqual(List<String> list1, List<String> list2) {
    if (list1.length != list2.length) return false;

    // Sort both lists to compare content regardless of order
    List<String> sortedList1 = List.from(list1)..sort();
    List<String> sortedList2 = List.from(list2)..sort();

    for (int i = 0; i < sortedList1.length; i++) {
      if (sortedList1[i] != sortedList2[i]) return false;
    }
    return true;
  }

  Future<void> _refreshCourseEnrollmentStatus() async {
    if (_isAuthenticated && courseDetail != null) {
      await _forceRefreshEnrolledCourses();

      // Check if course is enrolled
      bool isEnrolled = _isCourseEnrolled(courseDetail!);

      if (isEnrolled) {
        // Update course with enrollment data
        await _updateCourseWithEnrollmentData();
      } else {
        setState(() {
          _isEnrolled = false;
          _extractSubscriptionDetails();
        });
      }

      NyLogger.info(
          '🔄 After refresh - Enrolled: $_isEnrolled, Valid subscription: $_hasValidSubscription');
    }
  }

// Call this in your init method after loading enrolled course IDs:

  bool _isCourseEnrolled(Course course) {
    bool isEnrolled = _enrolledCourseIds.contains(course.id.toString());
    NyLogger.debug(
        '🔍 Course ${course.id} (${course.title}) enrollment status: $isEnrolled');
    NyLogger.debug('🔍 Enrolled course IDs: $_enrolledCourseIds');
    return isEnrolled;
  }

  Future<void> _fetchFreshEnrollmentData() async {
    if (!_isAuthenticated) return;

    try {
      var courseApiService = CourseApiService();
      List<dynamic> enrollmentsData = await courseApiService
          .getEnrollments(refresh: true)
          .timeout(Duration(seconds: 10));

      if (enrollmentsData.isNotEmpty) {
        List<String> enrolledIds = enrollmentsData
            .where((data) => data['course'] != null)
            .map((data) => data['course']['id'].toString())
            .toList();

        // ✅ Only update state if the data has actually changed
        if (!_listsEqual(_enrolledCourseIds, enrolledIds)) {
          setState(() {
            _enrolledCourseIds = enrolledIds;
          });

          // ✅ Ensure we save as List<String>
          try {
            await NyStorage.save('enrolled_course_ids', enrolledIds);
            NyLogger.info('✅ Updated enrolled course IDs: $enrolledIds');
          } catch (saveError) {
            NyLogger.error('Failed to save enrolled course IDs: $saveError');
          }
        }
      } else {
        if (_enrolledCourseIds.isNotEmpty) {
          setState(() {
            _enrolledCourseIds = [];
          });
          // Save empty list to cache
          await NyStorage.save('enrolled_course_ids', <String>[]);
        }
      }
    } catch (e) {
      NyLogger.error('❌ Failed to fetch fresh enrollment data: $e');
    }
  }

  Future<void> _loadEnrolledCourseIds() async {
    if (!_isAuthenticated) {
      setState(() {
        _enrolledCourseIds = [];
      });
      return;
    }

    try {
      // Always try to get from storage first (faster)
      dynamic cachedData = await NyStorage.read('enrolled_course_ids');
      List<String>? cachedIds;

      // ✅ Handle different data types that might be stored
      if (cachedData != null) {
        if (cachedData is List<String>) {
          cachedIds = cachedData;
        } else if (cachedData is List) {
          // Convert List<dynamic> to List<String>
          cachedIds = cachedData.map((item) => item.toString()).toList();
        } else if (cachedData is String) {
          // Handle case where single string is stored
          try {
            // Try to parse as JSON array
            var decoded = jsonDecode(cachedData);
            if (decoded is List) {
              cachedIds = decoded.map((item) => item.toString()).toList();
            } else {
              // Single string, convert to list
              cachedIds = [cachedData];
            }
          } catch (e) {
            // If JSON parsing fails, treat as single string
            cachedIds = [cachedData];
          }
        } else {
          // Unknown type, clear cache and start fresh
          NyLogger.debug(
              'Unknown cache type: ${cachedData.runtimeType}, clearing cache');
          await NyStorage.delete('enrolled_course_ids');
          cachedIds = null;
        }
      }

      if (cachedIds != null && cachedIds.isNotEmpty) {
        setState(() {
          _enrolledCourseIds = cachedIds!;
        });
        NyLogger.info(
            '✅ Loaded ${cachedIds.length} enrolled course IDs from cache: $cachedIds');

        // ✅ Also fetch fresh data in background to keep cache updated
        _fetchFreshEnrollmentData();
        return;
      }

      // If no valid cache, fetch from API
      await _fetchFreshEnrollmentData();
    } catch (e) {
      NyLogger.error('❌ Error loading enrolled course IDs: $e');

      // ✅ Clear corrupted cache and start fresh
      try {
        await NyStorage.delete('enrolled_course_ids');
        NyLogger.info('🧹 Cleared corrupted cache, fetching fresh data');
      } catch (clearError) {
        NyLogger.error('Failed to clear cache: $clearError');
      }

      setState(() {
        _enrolledCourseIds = [];
      });

      // Try to fetch fresh data
      await _fetchFreshEnrollmentData();
    }
  }

  Future<void> _updateCourseWithEnrollmentData() async {
    if (!_isAuthenticated || courseDetail == null) return;

    try {
      // Get fresh enrollment data
      var courseApiService = CourseApiService();
      List<dynamic> enrollmentsData = await courseApiService
          .getEnrollments(refresh: true)
          .timeout(Duration(seconds: 10));

      // Find enrollment data for this specific course
      Map<String, dynamic>? courseEnrollmentData;
      for (var enrollment in enrollmentsData) {
        if (enrollment['course'] != null &&
            enrollment['course']['id'].toString() ==
                courseDetail!.id.toString()) {
          courseEnrollmentData = enrollment;
          break;
        }
      }

      print("ghvsdjbkflngfbjgkbfsdkxvclbdskjbvjdbjvdjdv");
      print(courseEnrollmentData);
      if (courseEnrollmentData != null) {
        // Create UserEnrollment object from API data
        UserEnrollment userEnrollment = UserEnrollment(
          id: courseEnrollmentData['id'] ?? 0,
          planType: courseEnrollmentData['plan_type'] ?? '',
          planName: courseEnrollmentData['plan_name'] ?? '',
          expiryDate: courseEnrollmentData['expiry_date'] != null
              ? DateTime.tryParse(
                  courseEnrollmentData['expiry_date'].toString())
              : null,
          isActive: courseEnrollmentData['is_active'] == true,
          isExpired: courseEnrollmentData['is_expired'] == true,
        );

        // Create EnrollmentStatus object from API data
        EnrollmentStatus enrollmentStatus = EnrollmentStatus(
          status:
              courseEnrollmentData['is_active'] == true ? 'active' : 'inactive',
          message: 'Enrollment found',
          planType: courseEnrollmentData['plan_type'] ?? '',
          planName: courseEnrollmentData['plan_name'] ?? '',
          expiresOn: courseEnrollmentData['expiry_date'] != null
              ? DateTime.tryParse(
                  courseEnrollmentData['expiry_date'].toString())
              : null,
          isLifetime: courseEnrollmentData['plan_type'] == 'LIFETIME',
        );

        // Update the course object with enrollment data
        setState(() {
          courseDetail = courseDetail!.copyWith(
            isEnrolled: true,
            userEnrollment: userEnrollment,
            enrollmentStatus: enrollmentStatus,
          );

          _isEnrolled = true;
          _extractSubscriptionDetails();
        });

        NyLogger.info(
            '✅ Updated course ${courseDetail!.id} with enrollment data');
        NyLogger.info('   Plan: ${courseEnrollmentData['plan_name']}');
        NyLogger.info('   Type: ${courseEnrollmentData['plan_type']}');
        NyLogger.info('   Active: ${courseEnrollmentData['is_active']}');
        NyLogger.info('   Valid subscription: $_hasValidSubscription');
      } else {
        NyLogger.info(
            '⚠️ No enrollment data found for course ${courseDetail!.id}');
        setState(() {
          _isEnrolled = false;
          _extractSubscriptionDetails();
        });
      }
    } catch (e) {
      NyLogger.error('❌ Error updating course with enrollment data: $e');
    }
  }

  Future<void> _forceRefreshEnrolledCourses() async {
    // if (!_isAuthenticated) return;

    NyLogger.info('🔄 Force refreshing enrolled course IDs...');

    try {
      var courseApiService = CourseApiService();

      // Clear cache first
      await NyStorage.delete('enrolled_course_ids');

      // Fetch fresh data from API
      List<dynamic> enrollmentsData = await courseApiService
          .getEnrollments(refresh: true)
          .timeout(Duration(seconds: 15));

      if (enrollmentsData.isNotEmpty) {
        List<String> enrolledIds = enrollmentsData
            .where((data) => data['course'] != null)
            .map((data) => data['course']['id'].toString())
            .toList();

        setState(() {
          _enrolledCourseIds = enrolledIds;
        });

        // ✅ Save with proper type
        try {
          await NyStorage.save('enrolled_course_ids', enrolledIds);
          NyLogger.info(
              '✅ Force refresh completed. Enrolled IDs: $enrolledIds');
        } catch (saveError) {
          NyLogger.error('Failed to save after force refresh: $saveError');
        }
      } else {
        setState(() {
          _enrolledCourseIds = [];
        });
        await NyStorage.save('enrolled_course_ids', <String>[]);
        NyLogger.info('⚠️ No enrollments found after force refresh');
      }
    } catch (e) {
      NyLogger.error('❌ Force refresh failed: $e');
    }
  }

  @override
  void initState() {
    super.initState();

    Future.microtask(() async {
      try {
        await _videoService.initialize();
      } catch (e) {
        NyLogger.error('Error initializing video service: $e');
      }
    });

    _subscribeToDownloadProgress();
  }

  void _extractSubscriptionDetails() {
    if (courseDetail == null) {
      NyLogger.debug(
          '⚠️ courseDetail is null, cannot extract subscription details');
      return;
    }

    // Store previous values for comparison
    bool previousValidSubscription = _hasValidSubscription;

    _hasValidSubscription = courseDetail!.hasValidSubscription;
    _isLifetimeSubscription = courseDetail!.isLifetimeSubscription;
    _subscriptionExpiryDate = courseDetail!.subscriptionExpiryDate;
    _subscriptionStatus = courseDetail!.subscriptionStatus;
    _subscriptionPlanName = courseDetail!.subscriptionPlanName;

    // Debug logging
    NyLogger.info('📋 Subscription Details for Course ${courseDetail!.id}:');
    NyLogger.info('   📅 Enrolled: $_isEnrolled');
    NyLogger.info(
        '   ✅ Valid Subscription: $_hasValidSubscription (was: $previousValidSubscription)');
    NyLogger.info('   🔄 Lifetime: $_isLifetimeSubscription');
    NyLogger.info('   📅 Expiry Date: $_subscriptionExpiryDate');
    NyLogger.info('   📊 Status: $_subscriptionStatus');
    NyLogger.info('   🏷️ Plan: $_subscriptionPlanName');
  }

  Future<void> _refreshEnrollmentDetails(int courseId) async {
    try {
      Course updatedCourse =
          await _courseApiService.getCourseWithEnrollmentDetails(courseId);
      if (mounted) {
        setState(() {
          courseDetail = updatedCourse;
          _extractSubscriptionDetails();
        });
      }
    } catch (e) {
      NyLogger.error('Error refreshing enrollment details: $e');
    }
  }

  void _subscribeToDownloadProgress() {
    _downloadProgressSubscription = _videoService.progressStream.listen(
      (update) {
        if (!mounted) return;

        if (update.containsKey('type') && update['type'] == 'error') {
          if (update['errorType'] == 'diskSpace') {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(trans(update['message'] ?? "Storage error")),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      },
      onError: (error) {
        NyLogger.error('Error in download progress stream: $error');
      },
    );
  }

  @override
  void dispose() {
    if (_downloadProgressSubscription != null) {
      _downloadProgressSubscription!.cancel();
      _downloadProgressSubscription = null;
    }
    _scrollController.dispose();
    super.dispose();
  }

  @override
  LoadingStyle get loadingStyle => LoadingStyle.skeletonizer();

  @override
  get init => () async {
        setLoading(true, name: 'course_detail');
        setLoading(true, name: 'curriculum');
        setLoading(true, name: 'objectives');
        setLoading(true, name: 'requirements');

        _isAuthenticated = await Auth.isAuthenticated();

        try {
          Map<String, dynamic> data = widget.data();

          if (data.containsKey('course') && data['course'] != null) {
            courseDetail = data['course'];

            // ✅ FIRST: Extract subscription details from the course object
            _extractSubscriptionDetails();

            if (_isAuthenticated) {
              // ✅ Load enrolled course IDs
              await _loadEnrolledCourseIds();

              // ✅ Check enrollment and update with detailed enrollment data
              await getEnrolled(courseDetail);
            }
          } else {
            showToastDanger(description: "Course information is missing");
            pop();
            return;
          }
          await _refreshCourseEnrollmentStatus();
          // Continue with the rest of your initialization...
          int courseId = courseDetail!.id;
          List<Future> futures = [];

          // Load curriculum
          futures.add(_loadCourseCurriculum(courseId)
              .timeout(Duration(seconds: 10))
              .then((_) {
            if (mounted) {
              setLoading(false, name: 'curriculum');
              _calculateTotalDuration();
            }
          }).catchError((e) {
            NyLogger.error('Error loading curriculum: $e');
            curriculumItems = [];
            if (mounted) setLoading(false, name: 'curriculum');
            return <dynamic>[];
          }));

          // Load objectives
          futures.add(_loadCourseObjectives(courseId)
              .timeout(Duration(seconds: 10))
              .then((_) {
            if (mounted) setLoading(false, name: 'objectives');
          }).catchError((e) {
            NyLogger.error('Error loading objectives: $e');
            objectives = [];
            if (mounted) setLoading(false, name: 'objectives');
            return <dynamic>[];
          }));

          // Load requirements
          futures.add(_loadCourseRequirements(courseId)
              .timeout(Duration(seconds: 10))
              .then((_) {
            if (mounted) setLoading(false, name: 'requirements');
          }).catchError((e) {
            NyLogger.error('Error loading requirements: $e');
            requirements = [];
            if (mounted) setLoading(false, name: 'requirements');
            return <dynamic>[];
          }));

          await Future.wait(futures);

          if (mounted) {
            // Only check wishlist status if not enrolled (optimization)
            if (!_isEnrolled) {
              _checkWishlistStatus().catchError((e) {
                NyLogger.error('Error checking wishlist status: $e');
                return false;
              });
            }
          }

          _isInitializing = false;
        } catch (e) {
          NyLogger.error('Error initializing course detail: $e');
        } finally {
          if (mounted) {
            _isInitializing = false;
            setLoading(false, name: 'course_detail');
            setLoading(false, name: 'curriculum');
            setLoading(false, name: 'objectives');
            setLoading(false, name: 'requirements');
          }
        }
      };

  void _debugSubscriptionState() {
    NyLogger.info('🐛 DEBUGGING SUBSCRIPTION STATE:');
    NyLogger.info('   Course ID: ${courseDetail?.id}');
    NyLogger.info('   _isEnrolled: $_isEnrolled');
    NyLogger.info('   _hasValidSubscription: $_hasValidSubscription');
    NyLogger.info('   _isLifetimeSubscription: $_isLifetimeSubscription');
    NyLogger.info('   _subscriptionExpiryDate: $_subscriptionExpiryDate');
    NyLogger.info('   _subscriptionStatus: $_subscriptionStatus');
    NyLogger.info(
        '   courseDetail.hasValidSubscription: ${courseDetail?.hasValidSubscription}');
    NyLogger.info('   courseDetail.isEnrolled: ${courseDetail?.isEnrolled}');
    NyLogger.info(
        '   courseDetail.userEnrollment: ${courseDetail?.userEnrollment?.toJson()}');
    NyLogger.info(
        '   courseDetail.enrollmentStatus: ${courseDetail?.enrollmentStatus?.toJson()}');
    NyLogger.info('   enrolledCourseIds: $_enrolledCourseIds');
  }

  void _calculateTotalDuration() {
    if (!mounted) return;

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
              NyLogger.error('Error parsing duration: $e');
            }
          }
        }
      }

      int hours = totalSeconds ~/ 3600;
      int minutes = (totalSeconds % 3600) ~/ 60;

      setState(() {
        _totalDuration =
            hours > 0 ? "$hours hours $minutes minutes" : "$minutes minutes";
      });
    } catch (e) {
      NyLogger.error('Error calculating total duration: $e');
      setState(() {
        _totalDuration = "- minutes";
      });
    }
  }

  Future<void> getEnrolled(courseDetail) async {
    if (courseDetail == null) return;

    bool wasEnrolled = _isEnrolled;
    bool isCurrentlyEnrolled = _isCourseEnrolled(courseDetail);

    if (isCurrentlyEnrolled &&
        (courseDetail.userEnrollment == null ||
            courseDetail.enrollmentStatus == null)) {
      // Course is enrolled but missing enrollment details, fetch them
      NyLogger.info(
          '🔄 Course is enrolled but missing enrollment details, fetching...');
      await _updateCourseWithEnrollmentData();
    } else {
      // Just update the enrollment status
      if (wasEnrolled != isCurrentlyEnrolled || _isInitializing) {
        setState(() {
          _isEnrolled = isCurrentlyEnrolled;
          _extractSubscriptionDetails();
        });

        NyLogger.info(
            '🔄 Enrollment status updated: $_isEnrolled for course ${courseDetail?.id}');
        NyLogger.info('🔄 Subscription valid: $_hasValidSubscription');
      }
    }
  }

  @override
  get stateActions => {
        "course_enrolled": (Map<String, dynamic> data) async {
          if (data.containsKey('updatedCourse') &&
              data.containsKey('courseId') &&
              data['courseId'].toString() == courseDetail?.id.toString()) {
            try {
              Course updatedCourse = Course.fromJson(data['updatedCourse']);
              setState(() {
                courseDetail = updatedCourse;
                _isEnrolled = updatedCourse.isEnrolled;
                _extractSubscriptionDetails();
              });

              // ✅ Also update local enrolled course IDs
              if (!_enrolledCourseIds.contains(courseDetail!.id.toString())) {
                setState(() {
                  _enrolledCourseIds.add(courseDetail!.id.toString());
                });
                await NyStorage.save('enrolled_course_ids', _enrolledCourseIds);
              }

              NyLogger.info(
                  'Updated course enrollment status in CourseDetailPage');
            } catch (e) {
              NyLogger.error(
                  'Error updating course detail enrollment status: $e');
            }
          }
        },
      };

  Future<void> _loadCourseCurriculum(int courseId) async {
    try {
      List<dynamic> result =
          await _courseApiService.getCourseCurriculum(courseId);

      result.sort((a, b) => a['order'].compareTo(b['order']));

      if (mounted) {
        setState(() {
          curriculumItems = result;
        });
      }
    } catch (e) {
      NyLogger.error('Error loading curriculum: $e');
      if (mounted) {
        setState(() {
          curriculumItems = [];
        });
      }
      rethrow;
    }
  }

  void _showSubscriptionExpiredDialog() {
    showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(trans("Subscription Expired")),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(trans("Your subscription to this course has expired.")),
                SizedBox(height: 8),
                // ✅ Use course model data directly
                if (courseDetail?.subscriptionExpiryDate != null)
                  Text(
                    trans(
                        "Expired on: ${courseDetail!.subscriptionExpiryDate!.day}/${courseDetail!.subscriptionExpiryDate!.month}/${courseDetail!.subscriptionExpiryDate!.year}"),
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                SizedBox(height: 8),
                Text(trans(
                    "Please renew your subscription to continue accessing the course content.")),
              ],
            ),
            actions: [
              TextButton(
                child: Text(trans("Cancel")),
                onPressed: () => Navigator.pop(context),
              ),
              TextButton(
                child: Text(trans("Renew Subscription")),
                style: TextButton.styleFrom(foregroundColor: Colors.amber),
                onPressed: () {
                  Navigator.pop(context);
                  _handleSubscriptionRenewal();
                },
              ),
            ],
          );
        });
  }

  void _handleSubscriptionRenewal() {
    routeTo(EnrollmentPlanPage.path, data: {
      'course': courseDetail,
      'curriculum': curriculumItems,
      'isRenewal': true,
    });
  }

  Widget _buildSubscriptionExpiredBanner() {
    return Container(
      width: double.infinity,
      color: Colors.red.shade50,
      padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red, size: 18),
              SizedBox(width: 8),
              Text(
                trans("Subscription Expired"),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          SizedBox(height: 4),
          Text(
            trans(
                "Your subscription has expired. Please renew to continue accessing the course."),
            style: TextStyle(fontSize: 12),
          ),
          // ✅ Use course model data directly
          if (courseDetail?.subscriptionExpiryDate != null)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                trans(
                    "Expired on: ${courseDetail!.subscriptionExpiryDate!.day}/${courseDetail!.subscriptionExpiryDate!.month}/${courseDetail!.subscriptionExpiryDate!.year}"),
                style: TextStyle(fontSize: 10, color: Colors.grey[600]),
              ),
            ),
          SizedBox(height: 8),
          ElevatedButton(
            onPressed: _handleSubscriptionRenewal,
            child: Text(trans("Renew Subscription")),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              textStyle: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadCourseObjectives(int courseId) async {
    try {
      objectives = await _courseApiService.getCourseObjectives(courseId);
    } catch (e) {
      print('Error loading objectives: $e');
      objectives = [];
      rethrow;
    }
  }

  Future<void> _loadCourseRequirements(int courseId) async {
    try {
      requirements = await _courseApiService.getCourseRequirements(courseId);
    } catch (e) {
      print('Error loading requirements: $e');
      requirements = [];
      rethrow;
    }
  }

  Future<void> _checkWishlistStatus() async {
    try {
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
      rethrow;
    }
  }

  Future<void> _toggleWishlist() async {
    if (courseDetail == null) return;

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
        final wishlistData = await _courseApiService.getWishlist();
        final wishlistItems =
            wishlistData.map((data) => Wishlist.fromJson(data)).toList();

        final matchingItems = wishlistItems
            .where(
              (item) => item.courseId.toString() == courseDetail!.id.toString(),
            )
            .toList();

        if (matchingItems.isNotEmpty) {
          await _courseApiService.removeFromWishlist(matchingItems.first.id);
          setState(() {
            _isInWishlist = false;
          });
          showToastInfo(description: trans("Course removed from wishlist"));
        }
      } else {
        await _courseApiService.addToWishlist(courseDetail!.id);
        setState(() {
          _isInWishlist = true;
        });
        showToastSuccess(description: trans("Course added to wishlist"));
      }

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
    if (courseDetail == null || _isChecking) return;

    _isChecking = true;

    bool isAuthenticated = await Auth.isAuthenticated();
    if (!isAuthenticated) {
      _isChecking = false;
      confirmAction(() {
        routeTo(SigninPage.path);
      },
          title: trans("You need to login to enroll in courses."),
          confirmText: trans("Login"),
          dismissText: trans("Cancel"));
      return;
    }

    showLoadingDialog(trans("Checking subscription..."));

    try {
      bool hasActiveSubscription =
          await _purchaseApiService.hasActiveSubscription();

      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      if (!mounted) {
        _isChecking = false;
        return;
      }

      if (hasActiveSubscription) {
        showLoadingDialog(trans("Enrolling..."));

        await _courseApiService.enrollInCourse(courseDetail!.id);

        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }

        if (!mounted) {
          _isChecking = false;
          return;
        }

        showToastSuccess(description: trans("Successfully enrolled in course"));

        // ✅ After enrollment, update the course status locally
        setState(() {
          _isEnrolled = true;
          // ✅ Update course object to reflect enrollment
          courseDetail = courseDetail!.copyWith(isEnrolled: true);
          _extractSubscriptionDetails();
        });

        Future.microtask(() {
          updateState('/search_tab', data: "refresh_courses");
          updateState('/home_tab', data: "refresh_enrollments");
        });

        _navigateToCurriculum();
      } else {
        // Pass curriculum data to avoid extra API call
        routeTo(EnrollmentPlanPage.path,
            data: {'course': courseDetail, 'curriculum': curriculumItems});
      }
    } catch (e) {
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      NyLogger.error('Error handling enrollment: $e');
      if (mounted) {
        showToastDanger(
            description: trans("An error occurred, please try again"));
      }
    } finally {
      _isChecking = false;
    }
  }

  void _navigateToCurriculum() {
    if (!mounted || courseDetail == null) return;

    if (curriculumItems.isEmpty) {
      showLoadingDialog(trans("Preparing curriculum..."));
    }

    Future.microtask(() async {
      try {
        if (curriculumItems.isEmpty) {
          try {
            await _loadCourseCurriculum(courseDetail!.id);
            if (mounted && Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          } catch (e) {
            NyLogger.error('Error loading curriculum for navigation: $e');
            if (mounted && Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          }
        }

        // Pass curriculum data to avoid extra API call
        if (mounted) {
          routeTo(CourseCurriculumPage.path,
              data: {'course': courseDetail, 'curriculum': curriculumItems});
        }
      } catch (e) {
        NyLogger.error('Error navigating to curriculum: $e');
        if (mounted) {
          showToastDanger(
              description: trans("Failed to open course curriculum"));
        }
      }
    });
  }

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
    if (_isChecking) return;
    _isChecking = true;

    try {
      bool isAuthenticated = await Auth.isAuthenticated();
      if (!isAuthenticated) {
        _isChecking = false;
        confirmAction(() {
          routeTo(SigninPage.path);
        },
            title: trans("You need to login to watch videos"),
            confirmText: trans("Login"),
            dismissText: trans("Cancel"));
        return;
      }

      if (!_isEnrolled) {
        _isChecking = false;
        confirmAction(() {
          _handleEnrollment();
        },
            title: trans("Enrollment Required"),
            confirmText: trans("Enroll Now"),
            dismissText: trans("Cancel"));
        return;
      }

      if (!_hasValidSubscription) {
        _isChecking = false;
        _showSubscriptionExpiredDialog();
        return;
      }

      _isChecking = false;
      _navigateToCurriculum();
    } catch (e) {
      _isChecking = false;
      NyLogger.error('Error in _promptVideoDownload: $e');
    }
  }

  @override
  Widget view(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => pop(),
        ),
        title: SizedBox(),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.black),
            onPressed: _isInitializing
                ? null
                : () {
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
            setLoading(true, name: 'course_detail');
            await init();
          },
          child: SingleChildScrollView(
            controller: _scrollController,
            physics: AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCourseImage(),
                if (_isEnrolled && !_hasValidSubscription)
                  _buildSubscriptionExpiredBanner(),
                _buildCourseInfo(),
                _buildAchievementsSection(),
                _buildCurriculumSection(),
                _buildRequirementsSection(),
                _buildBottomAction(),
                SizedBox(height: 20),
              ],
            ),
          ),
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
                "Recorded",
                style: TextStyle(color: Colors.black, fontSize: 10),
              ),
            ],
          ),
          SizedBox(height: 24),

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
                  backgroundColor: Color(0xFFEFE458),
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
                  backgroundColor: Color(0xFFEFE458),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
              ),
            ),
          SizedBox(height: 12),

          // Only show wishlist button if not enrolled
          if (!_isEnrolled)
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
              ListView.builder(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                itemCount:
                    curriculumItems.length > 5 ? 5 : curriculumItems.length,
                itemBuilder: (context, index) {
                  final item = curriculumItems[index];
                  return _buildCurriculumItem(
                    index + 1,
                    item['title'] ?? 'Class Introduction Video',
                    item['duration'] ?? '5:05',
                    videoUrl: item['video_url'] ?? '',
                    onTap: () => _promptVideoDownload(index),
                  );
                },
              ),
            SizedBox(height: 10),
            if (_isEnrolled && curriculumItems.length > 5)
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
                        color: Color(0xFFE5A200),
                        fontSize: 14,
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward,
                      size: 16,
                      color: Color(0xFFE5A200),
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
                backgroundColor: Color(0xFFEFE458),
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
