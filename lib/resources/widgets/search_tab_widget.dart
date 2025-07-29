import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_app/resources/pages/course_detail_page.dart';
import 'package:flutter_app/resources/pages/purchased_course_detail_page.dart';
import 'package:flutter_app/resources/pages/signin_page.dart';
import 'package:nylo_framework/nylo_framework.dart';

import '../../app/models/course.dart';
import '../../app/models/enrollment.dart';
import '../../app/models/wishlist.dart';
import '../../utils/course_data.dart';
import '../../app/networking/course_api_service.dart';
import '../pages/enrollment_plan_page.dart';

class SearchTab extends StatefulWidget {
  const SearchTab({super.key});

  static String state = '/search_tab';

  @override
  createState() => _SearchTabState();
}

class _SearchTabState extends NyState<SearchTab> {
  final TextEditingController _searchController = TextEditingController();

  List<Course> _allCourses = [];
  List<Course> _filteredCourses = [];
  bool _isLoadingCourse = false;
  String? _loadingCourseId;

  // ✅ Add enrolled course IDs tracking
  List<String> _enrolledCourseIds = [];

  List<Wishlist> _wishlistItems = [];
  String _searchQuery = '';
  bool _isAuthenticated = false;

  _SearchTabState() {
    stateName = SearchTab.state;
  }

  @override
  LoadingStyle get loadingStyle => LoadingStyle.skeletonizer(
        child: _buildSkeletonLayout(),
      );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Check if we returned from another page and refresh enrollment status
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isAuthenticated) {
        _forceRefreshEnrolledCourses();
      }
    });
  }

  void _handleRouteReturn() async {
    if (_isAuthenticated) {
      NyLogger.info('🔄 Returned to SearchTab, refreshing enrollment status');
      await _forceRefreshEnrolledCourses();
    }
  }

  Future<void> _forceRefreshEnrolledCourses() async {
    if (!_isAuthenticated) return;

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

  // ✅ Updated stateActions to use the force refresh method
  @override
  get stateActions => {
        "refresh_courses": () async {
          await _fetchCourses(refresh: false);
        },
        "update_auth_status": (bool status) async {
          setState(() {
            _isAuthenticated = status;
          });
          if (_isAuthenticated) {
            await _loadEnrolledCourseIds();
            await _fetchUserSpecificData();
          } else {
            setState(() {
              _enrolledCourseIds = [];
            });
          }
        },
        "course_enrolled": (Map<String, dynamic> data) async {
          NyLogger.info('🎯 SearchTab received course_enrolled event: $data');

          if (data.containsKey('courseId')) {
            String courseId = data['courseId'].toString();

            // ✅ Add to enrolled course IDs
            if (!_enrolledCourseIds.contains(courseId)) {
              setState(() {
                _enrolledCourseIds.add(courseId);
              });

              // Update cache
              await NyStorage.save('enrolled_course_ids', _enrolledCourseIds);
              NyLogger.info('✅ Added course $courseId to enrolled list');
              NyLogger.info('   Updated enrolled IDs: $_enrolledCourseIds');
            } else {
              NyLogger.info('ℹ️ Course $courseId already in enrolled list');
            }
          }

          // ✅ Also force refresh to ensure we have the latest data
          await _forceRefreshEnrolledCourses();
        },
        "refresh_enrolled_courses": () async {
          await _forceRefreshEnrolledCourses();
        },
      };

  Future<void> _enrollInCourse(Course course) async {
    if (!_isAuthenticated) {
      confirmAction(() {
        routeTo(SigninPage.path);
      },
          title: trans("You need to login to enroll in courses."),
          confirmText: trans("Login"),
          dismissText: trans("Cancel"));
      return;
    }

    // ✅ Use local enrollment check
    if (_isCourseEnrolled(course)) {
      try {
        // ✅ Set loading state for this specific course
        setState(() {
          _isLoadingCourse = true;
          _loadingCourseId = course.id.toString();
        });

        // ✅ Find the enrollment ID for this course
        var courseApiService = CourseApiService();

        // First, get all enrollments to find the enrollment ID for this specific course
        List<dynamic> enrollmentsData = await courseApiService
            .getEnrollments(refresh: false)
            .timeout(Duration(seconds: 10));

        // Find the enrollment that matches this course
        Map<String, dynamic>? matchingEnrollment;
        for (var enrollmentData in enrollmentsData) {
          if (enrollmentData['course'] != null &&
              enrollmentData['course']['id'].toString() ==
                  course.id.toString()) {
            matchingEnrollment = enrollmentData;
            break;
          }
        }

        if (matchingEnrollment == null) {
          // Clear loading state
          setState(() {
            _isLoadingCourse = false;
            _loadingCourseId = null;
          });

          NyLogger.error('❌ No enrollment found for course ${course.id}');
          showToast(
            title: trans("Error"),
            description: trans("Enrollment not found for this course"),
            icon: Icons.error_outline,
            style: ToastNotificationStyleType.warning,
          );
          return;
        }

        int enrollmentId = matchingEnrollment['id'];
        NyLogger.info(
            '🚀 Found enrollment ID $enrollmentId for course ${course.id}');

        // ✅ Fetch complete enrollment details
        var completeEnrollmentData =
            await courseApiService.getEnrollmentDetails(enrollmentId,
                refresh: true // Always get fresh data when viewing a course
                );

        // Check if widget is still mounted
        if (!mounted) return;

        // Clear loading state
        setState(() {
          _isLoadingCourse = false;
          _loadingCourseId = null;
        });

        // Create complete enrollment object with full course details
        EnrollmentDetails completeEnrollment =
            EnrollmentDetails.fromJson(completeEnrollmentData);

        NyLogger.info('✅ Retrieved complete enrollment data:');
        NyLogger.info('   Course: ${completeEnrollment.course.title}');
        NyLogger.info('   Enrollment ID: ${completeEnrollment.id}');

        // Navigate to course detail page with complete data
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

        NyLogger.error('❌ Failed to load enrollment details: $e');

        showToast(
          title: trans("Error"),
          description:
              trans("Failed to load course details. Please try again."),
          icon: Icons.error_outline,
          style: ToastNotificationStyleType.warning,
        );

        // ✅ Fallback: navigate with basic course data
        Map<String, dynamic> courseData = {
          'course': course,
        };

        routeTo(PurchasedCourseDetailPage.path, data: courseData);
      }
      return;
    }

    // Navigate to course detail for enrollment
    await routeTo(CourseDetailPage.path, data: {
      'course': course,
    });

    // ✅ Refresh enrollments when returning from course detail
    _handleRouteReturn();
  }

  @override
  get init => () async {
        super.init();

        _isAuthenticated = await Auth.isAuthenticated();
        if (_isAuthenticated) {
          // ✅ Load enrolled course IDs first
          await _loadEnrolledCourseIds();
        }

        await _fetchCourses();

        _searchController.addListener(() {
          if (_searchController.text != _searchQuery) {
            _performSearch(_searchController.text);
          }
        });
      };

  // ✅ New method to load enrolled course IDs from cache
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

  // ✅ Helper method to check if a course is enrolled
  bool _isCourseEnrolled(Course course) {
    bool isEnrolled = _enrolledCourseIds.contains(course.id.toString());
    NyLogger.debug(
        '🔍 Course ${course.id} (${course.title}) enrollment status: $isEnrolled');
    return isEnrolled;
  }

// ✅ Helper method to compare two lists
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

  Future<void> _fetchCourses({bool refresh = false}) async {
    setLoading(true, name: 'fetch_courses');

    try {
      var courseApiService = CourseApiService();
      List<dynamic> coursesData = [];

      try {
        coursesData = await courseApiService.getAllCourses(refresh: refresh);
      } catch (e) {
        coursesData = await courseApiService.getAllCourses(refresh: refresh);
      }

      _allCourses = coursesData.map((data) => Course.fromJson(data)).toList();
      _filteredCourses = List.from(_allCourses);

      if (_isAuthenticated) {
        // ✅ Refresh enrolled course IDs and wishlist data
        await _loadEnrolledCourseIds();
        await _fetchWishlistData();
      }
    } catch (e) {
      NyLogger.error('Error fetching courses: $e');
      _filteredCourses = [];

      showToast(
          title: trans("Error"),
          description:
              trans("Failed to load courses from server, showing cached data"),
          icon: Icons.error_outline,
          style: ToastNotificationStyleType.warning);
    } finally {
      setLoading(false, name: 'fetch_courses');
    }
  }

  Future<void> _fetchWishlistData() async {
    if (!_isAuthenticated) return;

    setLoading(true, name: 'fetch_wishlist');

    try {
      var courseApiService = CourseApiService();
      List<dynamic> wishlistData = await courseApiService.getWishlist();

      _wishlistItems =
          wishlistData.map((data) => Wishlist.fromJson(data)).toList();

      NyLogger.debug('Loaded ${_wishlistItems.length} wishlist items');
    } catch (e) {
      NyLogger.error('Error fetching wishlist data: $e');

      if (e.toString() != "Exception: Not logged in") {
        showToastWarning(
            description: trans("Could not fetch your saved courses"));
      }
    } finally {
      setLoading(false, name: 'fetch_wishlist');
    }
  }

  Future<void> _fetchUserSpecificData() async {
    await _fetchWishlistData();
  }

  void _performSearch(String query) {
    setState(() {
      _searchQuery = query;

      if (query.isEmpty) {
        _filteredCourses = List.from(_allCourses);
        return;
      }

      String lowercaseQuery = query.toLowerCase();
      _filteredCourses = _allCourses.where((course) {
        return course.title.toLowerCase().contains(lowercaseQuery) ||
            course.smallDesc.toLowerCase().contains(lowercaseQuery) ||
            course.categoryName.toLowerCase().contains(lowercaseQuery);
      }).toList();
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _performSearch('');
  }

  Future<void> _toggleWishlist(Course course) async {
    if (!_isAuthenticated) {
      confirmAction(() {
        routeTo(SigninPage.path);
      },
          title: trans("You need to login to save courses to your wishlist."),
          confirmText: trans("Login"),
          dismissText: trans("Cancel"));
      return;
    }

    bool isInWishlist = _wishlistItems.any((c) => c.courseId == course.id);

    try {
      await lockRelease('toggle_wishlist_${course.id}', perform: () async {
        var courseApiService = CourseApiService();

        if (isInWishlist) {
          Wishlist? wishlistItem;
          try {
            wishlistItem =
                _wishlistItems.firstWhere((item) => item.courseId == course.id);
          } catch (e) {
            wishlistItem = null;
          }

          if (wishlistItem != null) {
            await courseApiService.removeFromWishlist(wishlistItem.id);
            showToastInfo(description: trans("Course removed from wishlist"));

            setState(() {
              _wishlistItems.removeWhere((item) => item.courseId == course.id);
            });

            updateState('/wishlist_tab', data: "refresh_wishlist");
          }
        } else {
          var response = await courseApiService.addToWishlist(course.id);

          if (response != null) {
            Wishlist newWishlistItem = Wishlist.fromJson(response);

            setState(() {
              _wishlistItems.add(newWishlistItem);
            });
          }

          showToastSuccess(description: trans("Course added to wishlist"));
          updateState('/wishlist_tab', data: "refresh_wishlist");
        }
      });
    } catch (e) {
      showToastDanger(description: trans("Failed to update wishlist"));
      NyLogger.error('Error toggling wishlist: $e');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget view(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchBar(),
            Expanded(
              child: afterLoad(
                loadingKey: 'fetch_courses',
                child: () => _buildContent(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: Colors.grey.shade200,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.search, color: Colors.grey),
                  SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: trans("Search for any course of your choice"),
                        border: InputBorder.none,
                        hintStyle: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      onSubmitted: (value) {
                        FocusScope.of(context).unfocus();
                      },
                    ),
                  ),
                  if (_searchQuery.isNotEmpty)
                    GestureDetector(
                      onTap: _clearSearch,
                      child: Icon(Icons.close, color: Colors.grey, size: 18),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(width: 12),
          IconButton(
            icon: Icon(Icons.tune, color: Colors.black),
            onPressed: () {
              _showFilterDialog();
            },
          ),
          if (_isAuthenticated)
            IconButton(
              icon: Icon(Icons.refresh, color: Colors.black),
              onPressed: () async {
                await _fetchCourses(refresh: false);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_allCourses.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'bro.png',
              width: 150,
              height: 150,
              errorBuilder: (context, error, stackTrace) {
                return Icon(
                  Icons.search,
                  size: 80,
                  color: Colors.grey.shade400,
                );
              },
            ).localAsset(),
            SizedBox(height: 24),
            Text(
              trans("Learn exciting new things"),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              trans("Search for courses, Style, and Tutors"),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
            if (!_isAuthenticated)
              Padding(
                padding: const EdgeInsets.only(top: 24.0),
                child: ElevatedButton(
                  onPressed: () {
                    routeTo(SigninPage.path);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    trans("Login to access your courses"),
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    if (_filteredCourses.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 80,
              color: Colors.grey.shade400,
            ),
            SizedBox(height: 24),
            Text(
              trans("No results found for \"$_searchQuery\""),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              trans("Try a different search term"),
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "${_filteredCourses.length} ${trans("results")}",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              GestureDetector(
                onTap: _showSortOptions,
                child: Row(
                  children: [
                    Text(
                      trans("Sort by"),
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 12,
                      ),
                    ),
                    Icon(Icons.arrow_drop_down, color: Colors.grey.shade700),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.symmetric(horizontal: 16),
            itemCount: _filteredCourses.length,
            itemBuilder: (context, index) {
              final course = _filteredCourses[index];

              bool isInWishlist =
                  _wishlistItems.any((c) => c.courseId == course.id);

              // ✅ Use local enrollment check
              bool isEnrolled = _isCourseEnrolled(course);

              return _buildCourseListItem(course,
                  isInWishlist: isInWishlist, isEnrolled: isEnrolled);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCourseListItem(Course course,
      {bool isInWishlist = false, bool isEnrolled = false}) {
    bool isLoading =
        _isLoadingCourse && _loadingCourseId == course.id.toString();

    return InkWell(
      onTap: () => _navigateToCourseDetail(course),
      child: Container(
        margin: EdgeInsets.only(bottom: 16),
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
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          course.title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          maxLines: 3,
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
                        if (course.id == 5 || course.id == 1)
                          Text(
                            "Pragya Valley, Deepika Nair",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        SizedBox(height: 4),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                course.categoryName,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ),
                            if (course.id == 7)
                              Container(
                                margin: EdgeInsets.only(left: 8),
                                padding: EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  "LIVE",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            if (isEnrolled)
                              Container(
                                margin: EdgeInsets.only(left: 8),
                                padding: EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  trans("ENROLLED"),
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (_isAuthenticated)
                  Padding(
                    padding: const EdgeInsets.only(top: 12.0, right: 12.0),
                    child: GestureDetector(
                      onTap: () => _toggleWishlist(course),
                      child: Icon(
                        isInWishlist ? Icons.favorite : Icons.favorite_border,
                        color: isInWishlist ? Colors.red : Colors.grey,
                        size: 24,
                      ),
                    ),
                  ),
              ],
            ),
            if (_isAuthenticated)
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ElevatedButton(
                      // ✅ Disable button when loading
                      onPressed:
                          isLoading ? null : () => _enrollInCourse(course),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            isEnrolled ? Colors.grey.shade200 : Colors.amber,
                        padding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                                  isEnrolled ? Colors.black : Colors.white,
                                ),
                              ),
                            )
                          : Text(
                              isEnrolled
                                  ? trans("View Course")
                                  : trans('Enroll Now'),
                              style: TextStyle(
                                color:
                                    isEnrolled ? Colors.black87 : Colors.white,
                                fontSize: 12,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _navigateToCourseDetail(Course course) {
    routeTo('/course-detail', data: {'course': course});
  }

  void _showFilterDialog() {
    final List<String> categories =
        _allCourses.map((course) => course.categoryName).toSet().toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Container(
        padding: EdgeInsets.all(16),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              trans("Filter Courses"),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Divider(),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ExpansionTile(
                      leading: Icon(Icons.category),
                      title: Text(trans("By Category")),
                      children: [
                        ...categories.map((category) => ListTile(
                              contentPadding: EdgeInsets.only(left: 72),
                              title: Text(category),
                              onTap: () {
                                pop();
                                setState(() {
                                  _filteredCourses = _allCourses
                                      .where((course) =>
                                          course.categoryName == category)
                                      .toList();
                                });
                              },
                            ))
                      ],
                    ),

                    ListTile(
                      leading: Icon(Icons.star),
                      title: Text(trans("Highest Rated")),
                      onTap: () {
                        pop();
                        setState(() {
                          _filteredCourses.sort((a, b) => b.id.compareTo(a.id));
                        });
                      },
                    ),

                    ListTile(
                      leading: Icon(Icons.timer),
                      title: Text(trans("New Courses")),
                      onTap: () {
                        pop();
                        setState(() {
                          _filteredCourses = _allCourses
                              .where((course) => [7, 8, 9].contains(course.id))
                              .toList();
                        });
                      },
                    ),

                    if (_isAuthenticated)
                      ListTile(
                        leading: Icon(Icons.favorite),
                        title: Text(trans("Wishlist Only")),
                        onTap: () {
                          pop();
                          setState(() {
                            _filteredCourses = _allCourses
                                .where((course) => _wishlistItems
                                    .any((c) => c.courseId == course.id))
                                .toList();
                          });
                        },
                      ),

                    // ✅ Updated to use local enrollment check
                    if (_isAuthenticated)
                      ListTile(
                        leading: Icon(Icons.school),
                        title: Text(trans("Enrolled Only")),
                        onTap: () {
                          pop();
                          setState(() {
                            _filteredCourses = _allCourses
                                .where((course) => _isCourseEnrolled(course))
                                .toList();
                          });
                        },
                      ),
                  ],
                ),
              ),
            ),
            Divider(),
            Center(
              child: ElevatedButton(
                onPressed: () {
                  pop();
                  setState(() {
                    _filteredCourses = List.from(_allCourses);
                    _searchController.clear();
                    _searchQuery = '';
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber.withOpacity(0.9),
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: Text(
                  trans("Show All Courses"),
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSortOptions() {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Container(
        padding: EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              trans("Sort By"),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Divider(),
            ListTile(
              title: Text(trans("Alphabetical (A-Z)")),
              onTap: () {
                pop();
                setState(() {
                  _filteredCourses.sort((a, b) => a.title.compareTo(b.title));
                });
              },
            ),
            ListTile(
              title: Text(trans("Alphabetical (Z-A)")),
              onTap: () {
                pop();
                setState(() {
                  _filteredCourses.sort((a, b) => b.title.compareTo(a.title));
                });
              },
            ),
            ListTile(
              title: Text(trans("Category")),
              onTap: () {
                pop();
                setState(() {
                  _filteredCourses
                      .sort((a, b) => a.categoryName.compareTo(b.categoryName));
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonLayout() {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  bottom: BorderSide(
                    color: Colors.grey.shade200,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Container(
                    width: 24,
                    height: 24,
                    color: Colors.grey.shade300,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.all(16),
                itemCount: 5,
                itemBuilder: (context, index) {
                  return Container(
                    margin: EdgeInsets.only(bottom: 16),
                    height: 120,
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
                                  height: 12,
                                  width: 150,
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
          ],
        ),
      ),
    );
  }
}
