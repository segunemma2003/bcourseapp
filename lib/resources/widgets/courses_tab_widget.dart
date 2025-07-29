import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // For kDebugMode
import 'package:flutter_app/resources/pages/base_navigation_hub.dart';
import 'package:flutter_app/resources/pages/purchased_course_detail_page.dart';
import 'package:nylo_framework/nylo_framework.dart';

import '../../app/models/course.dart';
import '../../app/models/enrollment.dart'; // Now includes EnrollmentDetails
import '../../app/networking/course_api_service.dart';

class CoursesTab extends StatefulWidget {
  const CoursesTab({super.key});

  static String state = '/courses_tab';

  @override
  createState() => _CoursesTabState();
}

class _CoursesTabState extends NyState<CoursesTab> with WidgetsBindingObserver {
  List<Enrollment> _enrollments = [];
  bool _hasCourses = false;
  bool _isAuthenticated = false;
  Map _courseProgress = {};
  bool _isLoadingCourse = false;
  String? _loadingCourseId;

  _CoursesTabState() {
    stateName = CoursesTab.state;
  }

  @override
  LoadingStyle get loadingStyle => LoadingStyle.skeletonizer(
        child: _buildSkeletonLayout(),
      );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    // Clear any remaining dialogs before disposing
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        while (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      } catch (e) {
        // Ignore errors when disposing
      }
    });

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && mounted) {
      // Clear any loading dialogs when app resumes
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          // Clear any potential loading dialogs
          while (Navigator.of(context).canPop()) {
            try {
              Navigator.of(context).pop();
            } catch (e) {
              break; // Exit if we can't pop anymore
            }
          }

          // Clear loading states
          try {
            setLoading(false, name: 'fetch_enrollments');
          } catch (e) {
            NyLogger.debug('Error clearing loading state on resume: $e');
          }
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Ensure clean state on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        try {
          setLoading(false, name: 'fetch_enrollments');
        } catch (e) {
          // Ignore errors when clearing loading state
        }
      }
    });
  }

  @override
  get init => () async {
        super.init();

        _isAuthenticated = await Auth.isAuthenticated();
        await _fetchEnrollments();
      };

  @override
  stateUpdated(data) async {
    if (data == "refresh_enrolled_courses") {
      await _fetchEnrollments(refresh: true);
    } else if (data == "update_auth_status") {
      setState(() {
        _isAuthenticated = true;
      });
      await _fetchEnrollments(refresh: true);
    }

    return super.stateUpdated(data);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Clear any loading states when returning to this page
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // Check if there are any dialogs open and close them
        while (Navigator.of(context).canPop()) {
          final route = ModalRoute.of(context);
          // Only pop if it's a dialog, not a regular page
          if (route?.settings.name == null) {
            try {
              Navigator.of(context).pop();
            } catch (e) {
              break;
            }
          } else {
            break;
          }
        }

        try {
          setLoading(false, name: 'fetch_enrollments');
        } catch (e) {
          NyLogger.debug('Error clearing loading state: $e');
        }
      }
    });
  }

  Future<void> _loadCourseProgress() async {
    if (_enrollments.isEmpty) return;

    for (var enrollment in _enrollments) {
      try {
        String key = 'course_progress_${enrollment.course.id}';
        var savedProgress = await NyStorage.read(key);

        if (savedProgress != null) {
          var completedLessons = (savedProgress is Map &&
                  savedProgress.containsKey('completedLessons'))
              ? savedProgress['completedLessons']
              : {};

          var completedCount =
              completedLessons.values.where((v) => v == true).length;

          int totalVideos = enrollment.totalCurriculum ?? 0;
          double progress =
              totalVideos > 0 ? completedCount / totalVideos : 0.0;

          setState(() {
            _courseProgress[enrollment.course.id.toString()] = progress;
          });
        } else {
          setState(() {
            _courseProgress[enrollment.course.id.toString()] = 0.0;
          });
        }
      } catch (e) {
        NyLogger.error(
            'Failed to load progress for course ${enrollment.course.id}: $e');
        setState(() {
          _courseProgress[enrollment.course.id.toString()] = 0.0;
        });
      }
    }
  }

  // ✅ Updated to use direct enrollment API
  Future<void> _fetchEnrollments({bool refresh = false}) async {
    setLoading(true, name: 'fetch_enrollments');

    try {
      if (!_isAuthenticated) {
        NyLogger.info('🔐 User not authenticated');
        setState(() {
          _enrollments = [];
          _hasCourses = false;
        });
        return;
      }

      var courseApiService = CourseApiService();

      try {
        NyLogger.info('🚀 Fetching enrollments directly from enrollment API');

        // ✅ Use the enrollment API directly
        List<dynamic> enrollmentsData = await courseApiService
            .getEnrolledCourses(refresh: refresh)
            .timeout(Duration(seconds: 15), onTimeout: () {
          NyLogger.error('getEnrolledCourses timed out');
          throw Exception('Request timed out');
        });

        if (enrollmentsData.isNotEmpty) {
          NyLogger.info('📊 Raw enrollment API data sample:');
          if (enrollmentsData.isNotEmpty) {
            final firstEnrollment = enrollmentsData[0];
            NyLogger.info('   Raw enrollment data: $firstEnrollment');
            NyLogger.info(
                '   is_active value: ${firstEnrollment['is_active']}');
            NyLogger.info('   plan_type: ${firstEnrollment['plan_type']}');
            NyLogger.info('   expiry_date: ${firstEnrollment['expiry_date']}');
          }

          // Convert to Enrollment objects
          _enrollments = enrollmentsData.map((data) {
            NyLogger.info(
                '🔄 Converting enrollment ${data['id']} for course ${data['course']['id']}');

            try {
              Enrollment enrollment = Enrollment.fromJson(data);
              NyLogger.info('   ✅ Enrollment converted successfully');
              NyLogger.info('   - Course: ${enrollment.course.title}');
              NyLogger.info('   - Plan: ${enrollment.planType}');
              NyLogger.info('   - Is Valid: ${enrollment.isValid}');
              NyLogger.info('   - Status: ${enrollment.subscriptionStatus}');

              return enrollment;
            } catch (e) {
              NyLogger.error('   ❌ Error converting enrollment: $e');
              rethrow;
            }
          }).toList();

          // Filter only valid enrollments
          var validEnrollments = _enrollments.where((enrollment) {
            bool isValid = enrollment.isValid;
            NyLogger.info(
                '🔍 Enrollment ${enrollment.id} for course ${enrollment.course.title}: isValid = $isValid');
            return isValid;
          }).toList();

          _enrollments = validEnrollments;
          _hasCourses = _enrollments.isNotEmpty;

          NyLogger.info(
              '🎯 FINAL RESULT: ${_enrollments.length} valid enrollments');
          for (var enrollment in _enrollments) {
            NyLogger.info(
                '   📚 ${enrollment.course.title} (ID: ${enrollment.course.id}) - ${enrollment.subscriptionStatus}');
          }

          // ✅ Save enrolled course IDs for fallback
          if (_enrollments.isNotEmpty) {
            List<String> enrolledIds = _enrollments
                .map((enrollment) => enrollment.course.id.toString())
                .toList();
            await NyStorage.save('enrolled_course_ids', enrolledIds);
            NyLogger.info('💾 Saved enrolled course IDs: $enrolledIds');
          }
        } else {
          _enrollments = [];
          _hasCourses = false;
          NyLogger.info('⚠️ No enrollments found in API response');
        }
      } catch (e) {
        NyLogger.error('❌ Enrollment API Error: $e');

        // ✅ Enhanced fallback to local storage
        try {
          List<String>? enrolledCourseIds =
              await NyStorage.read('enrolled_course_ids');

          if (enrolledCourseIds != null && enrolledCourseIds.isNotEmpty) {
            NyLogger.info(
                '🔄 Falling back to local storage for enrolled course IDs');

            // Try to get enrollment data from cache
            var cachedEnrollments = await courseApiService.getEnrollments();

            // ignore: unnecessary_null_comparison
            if (cachedEnrollments != null) {
              NyLogger.info('✅ Using cached enrollment data');
              _enrollments = cachedEnrollments
                  .map((data) => Enrollment.fromJson(data))
                  .where((enrollment) => enrollment.isValid)
                  .toList();
              _hasCourses = _enrollments.isNotEmpty;
            } else {
              // Fallback to getting individual course details
              NyLogger.info(
                  '🔄 Fetching individual course details as fallback');
              List<Enrollment> fallbackEnrollments = [];

              for (String courseIdStr in enrolledCourseIds) {
                try {
                  int courseId = int.parse(courseIdStr);
                  var courseData = await courseApiService
                      .getCourseDetails(courseId, refresh: false);

                  // Create a mock enrollment object
                  var mockEnrollmentData = {
                    'id': 0,
                    'course': courseData,
                    'date_enrolled': DateTime.now().toIso8601String(),
                    'plan_type': 'LIFETIME', // Assume lifetime for fallback
                    'plan_name': 'Lifetime',
                    'expiry_date': null,
                    'amount_paid': '0.00',
                    'is_active': true,
                    'is_expired': false,
                  };

                  Enrollment enrollment =
                      Enrollment.fromJson(mockEnrollmentData);
                  fallbackEnrollments.add(enrollment);
                } catch (e) {
                  NyLogger.error(
                      '❌ Failed to create fallback enrollment for course $courseIdStr: $e');
                }
              }

              _enrollments = fallbackEnrollments;
              _hasCourses = _enrollments.isNotEmpty;
            }

            NyLogger.info(
                '✅ Fallback: Loaded ${_enrollments.length} enrollments');
          } else {
            _enrollments = [];
            _hasCourses = false;
          }
        } catch (fallbackError) {
          NyLogger.error(
              '❌ Local storage fallback also failed: $fallbackError');
          _enrollments = [];
          _hasCourses = false;
        }
      }
    } catch (e) {
      NyLogger.error('❌ Failed to fetch enrollments: $e');

      String userMessage = "Failed to load your courses";
      if (e.toString().contains("timeout")) {
        userMessage =
            "Connection timeout - please check your internet and try again";
      } else if (e.toString().contains("500")) {
        userMessage = "Server temporarily unavailable - please try again";
      }

      showToast(
          title: trans("Error"),
          description: trans(userMessage),
          icon: Icons.error_outline,
          style: ToastNotificationStyleType.warning);

      setState(() {
        _enrollments = [];
        _hasCourses = false;
      });
    } finally {
      setLoading(false, name: 'fetch_enrollments');
    }
  }

  void _onGetStartedPressed() async {
    routeTo(BaseNavigationHub.path, tabIndex: 1);
  }

  void _onStartCourse(Enrollment enrollment) async {
    try {
      // Set loading state instead of showing dialog
      setState(() {
        _isLoadingCourse = true;
        _loadingCourseId = enrollment.id.toString();
      });

      // Fetch complete enrollment details
      var courseApiService = CourseApiService();
      NyLogger.info(
          '🚀 Fetching complete enrollment details for enrollment ID: ${enrollment.id}');

      var completeEnrollmentData = await courseApiService
          .getEnrollmentDetails(enrollment.id, refresh: true);

      // Check if widget is still mounted
      if (!mounted) return;

      // Clear loading state
      setState(() {
        _isLoadingCourse = false;
        _loadingCourseId = null;
      });

      // Create complete enrollment object
      EnrollmentDetails completeEnrollment =
          EnrollmentDetails.fromJson(completeEnrollmentData);

      NyLogger.info('✅ Retrieved complete course data:');
      NyLogger.info('   Course: ${completeEnrollment.course.title}');

      // Navigate to course detail page
      Map<String, dynamic> courseData = {
        'enrollment': completeEnrollment,
        'course': completeEnrollment.course,
      };

      routeTo(PurchasedCourseDetailPage.path, data: courseData);
    } catch (e) {
      if (!mounted) return;

      // Clear loading state
      setState(() {
        _isLoadingCourse = false;
        _loadingCourseId = null;
      });

      NyLogger.error('❌ Failed to load course details: $e');

      showToast(
        title: trans("Error"),
        description: trans("Failed to load course details. Please try again."),
        icon: Icons.error_outline,
        style: ToastNotificationStyleType.warning,
      );

      // Fallback navigation
      Map<String, dynamic> courseData = {
        'enrollment': enrollment,
        'course': enrollment.course,
      };

      return;

      // routeTo(PurchasedCourseDetailPage.path, data: courseData);
    }
  }

  Widget _buildCourseItemButton(Enrollment enrollment) {
    bool isLoading =
        _isLoadingCourse && _loadingCourseId == enrollment.id.toString();
    bool isValid = enrollment.isValid;
    double progressPercentage =
        _courseProgress[enrollment.course.id.toString()] ?? 0.0;

    return ElevatedButton(
      onPressed: isLoading ? null : () => _onStartCourse(enrollment),
      style: ElevatedButton.styleFrom(
        backgroundColor: isValid ? Colors.amber : Colors.red,
        foregroundColor: isValid ? Colors.black : Colors.white,
        elevation: 0,
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      child: isLoading
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isValid ? Colors.black : Colors.white,
                ),
              ),
            )
          : Text(
              !isValid
                  ? trans("Renew")
                  : (progressPercentage > 0
                      ? trans("Continue")
                      : trans("Begin Course")),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
    );
  }

  Future<void> _onRefresh() async {
    await lockRelease('refresh_enrollments', perform: () async {
      try {
        await _fetchEnrollments(refresh: true);

        if (_hasCourses) {
          showToastSuccess(
              description: trans("Courses refreshed successfully"));
        } else if (_isAuthenticated) {
          showToastInfo(description: trans("No enrolled courses found"));
        }
      } catch (e) {
        NyLogger.error('Refresh failed: $e');
        showToastWarning(
            description: trans("Refresh failed - using cached data"));
      }
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
              // ✅ DEBUG: Force cache clear button (remove in production)
              if (kDebugMode)
                IconButton(
                  icon: Icon(Icons.clear_all, color: Colors.red),
                  onPressed: () async {
                    NyLogger.info('🧹 FORCE CLEARING ENROLLMENT CACHES');
                    await NyStorage.delete('enrolled_courses');
                    await NyStorage.delete('enrolled_course_ids');
                    await _fetchEnrollments(refresh: true);
                  },
                ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          child: afterLoad(
            loadingKey: 'fetch_enrollments',
            child: () => Column(
              children: [
                // ✅ DEBUG INFO (uncomment for debugging)
                // if (kDebugMode)
                //   Container(
                //     width: double.infinity,
                //     color: Colors.orange.shade50,
                //     padding: EdgeInsets.all(8),
                //     child: Text(
                //       'DEBUG: Auth: $_isAuthenticated | Enrollments: ${_enrollments.length} | Has: $_hasCourses',
                //       style: TextStyle(fontSize: 10),
                //       textAlign: TextAlign.center,
                //     ),
                //   ),
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
    if (_enrollments.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.separated(
      padding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      itemCount: _enrollments.length,
      separatorBuilder: (context, index) => SizedBox(height: 16),
      itemBuilder: (context, index) {
        final enrollment = _enrollments[index];
        return _buildCourseItem(enrollment);
      },
    );
  }

  Widget _buildCourseItem(Enrollment enrollment) {
    double progressPercentage =
        _courseProgress[enrollment.course.id.toString()] ?? 0.0;

    bool isValid = enrollment.isValid;
    bool isLifetime = enrollment.isLifetimePlan;
    int? daysRemaining = enrollment.daysRemaining;
    String subscriptionStatus = enrollment.subscriptionStatus;

    // Format expiry date for display
    String? expiryDateText;
    if (enrollment.expiryDate != null && !isLifetime) {
      expiryDateText =
          "${enrollment.expiryDate!.day}/${enrollment.expiryDate!.month}/${enrollment.expiryDate!.year}";
    }

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
          // Show warning banner for expired subscriptions
          if (!isValid)
            Container(
              width: double.infinity,
              color: Colors.red.shade50,
              padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.red, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      expiryDateText != null
                          ? trans("Expired on") + " $expiryDateText"
                          : trans("Subscription Expired"),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(8),
                  bottomLeft: isValid ? Radius.circular(8) : Radius.zero,
                ),
                child: Image.network(
                  enrollment.course.image,
                  width: 140, // Increased width to make it rectangular
                  height: 100, // Keep height for rectangular shape
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 140, // Increased width to make it rectangular
                      height: 100, // Keep height for rectangular shape
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
                        enrollment.course.title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 4),
                      Text(
                        enrollment.course.smallDesc,
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
                          Row(
                            children: [
                              Text(
                                "${(progressPercentage * 100).toInt()}% ${trans("Complete")}",
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              // Show subscription status
                              if (isLifetime) ...[
                                SizedBox(width: 8),
                                Text(
                                  "• ${trans("Lifetime")}",
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.green.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ] else if (daysRemaining != null &&
                                  daysRemaining > 0) ...[
                                SizedBox(width: 8),
                                Text(
                                  "• $daysRemaining ${trans("days left")}",
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: daysRemaining <= 7
                                        ? Colors.orange.shade700
                                        : Colors.blue.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ] else if (expiryDateText != null) ...[
                                SizedBox(width: 8),
                                Text(
                                  "• ${trans("Expired")} $expiryDateText",
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.red,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: progressPercentage,
                              backgroundColor: Colors.grey.shade200,
                              color:
                                  isValid ? Colors.amber : Colors.red.shade300,
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
                      "${enrollment.totalCurriculum ?? 0} ${trans("videos")}",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    SizedBox(width: 16),
                    Text(
                      "₹${enrollment.amountPaid.toStringAsFixed(0)}",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                // ✅ Use the custom loading button instead of the old one
                _buildCourseItemButton(enrollment),
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
