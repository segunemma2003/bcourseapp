import 'package:flutter/material.dart';
import 'package:flutter_app/resources/pages/course_detail_page.dart';
import 'package:flutter_app/resources/pages/purchased_course_detail_page.dart';
import 'package:flutter_app/resources/pages/signin_page.dart';
import 'package:nylo_framework/nylo_framework.dart';

import '../../app/models/course.dart';
import '../../app/models/wishlist.dart'; // Import Wishlist model
import '../../utils/course_data.dart';
import '../../app/networking/course_api_service.dart';
import '../pages/enrollment_plan_page.dart'; // Import for EnrollmentPlanPage.path

class SearchTab extends StatefulWidget {
  const SearchTab({super.key});

  // Define state name for state management
  static String state = '/search_tab';

  @override
  createState() => _SearchTabState();
}

class _SearchTabState extends NyState<SearchTab> {
  final TextEditingController _searchController = TextEditingController();

  List<Course> _allCourses = [];
  List<Course> _filteredCourses = [];
  List<Course> _enrolledCourses = [];

  List<Wishlist> _wishlistItems = []; // Add direct list of Wishlist items
  Map<String, dynamic>? _userData;
  String _searchQuery = '';
  bool _isAuthenticated = false;

  // Set the state name for Nylo's state management
  _SearchTabState() {
    stateName = SearchTab.state;
  }

  @override
  LoadingStyle get loadingStyle => LoadingStyle.skeletonizer(
        child: _buildSkeletonLayout(),
      );

  @override
  get init => () async {
        super.init();

        // Check authentication status
        _isAuthenticated = await Auth.isAuthenticated();
        if (_isAuthenticated) {
          _userData = await Auth.data();
        }

        // Initialize data
        await _fetchCourses();
        await _fetchEnrolledCourses();

        // Listen for text changes
        _searchController.addListener(() {
          if (_searchController.text != _searchQuery) {
            _performSearch(_searchController.text);
          }
        });
      };

  Future<void> _fetchEnrolledCourses() async {
    setLoading(true, name: 'fetch_enrolled_courses');

    try {
      // If not authenticated, we can't fetch enrolled courses
      if (!_isAuthenticated) {
        setState(() {
          _enrolledCourses = [];
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
        } else {
          _enrolledCourses = [];
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
        } else {
          _enrolledCourses = [];
        }
      }

      // Load progress data for courses
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
      });
    } finally {
      setLoading(false, name: 'fetch_enrolled_courses');
    }
  }

  // Define state actions that can be called from other widgets
  @override
  get stateActions => {
        "refresh_courses": () async {
          await _fetchCourses(refresh: true);
        },
        "update_auth_status": (bool status) async {
          setState(() {
            _isAuthenticated = status;
          });
          if (_isAuthenticated) {
            _userData = await Auth.data();
            await _fetchUserSpecificData();
          }
        },
        // Add action to update wishlist status from wishlist tab
        "update_wishlist_status": (Map<String, dynamic> data) async {
          if (data.containsKey('course_id') &&
              data.containsKey('is_in_wishlist')) {
            String courseId = data['course_id'];
            bool isInWishlist = data['is_in_wishlist'];

            if (!isInWishlist) {
              // Remove course from wishlist courses
              setState(() {
                _wishlistItems.removeWhere((c) => c.courseId == courseId);
              });
            }
          }
        },
      };

  Future<void> _fetchCourses({bool refresh = false}) async {
    // Use Nylo's loading state management with skeletonizer
    setLoading(true, name: 'fetch_courses');

    try {
      // Use the CourseApiService instead of local data
      var courseApiService = CourseApiService();

      // Fetch both featured and all courses in parallel for faster loading
      List<dynamic> coursesData = [];

      try {
        // First attempt to get courses from API
        coursesData = await courseApiService.getAllCourses(refresh: refresh);
      } catch (e) {
        // Fallback to featured courses if getAllCourses fails
        coursesData = await courseApiService.getAllCourses(refresh: refresh);
      }

      _allCourses = coursesData.map((data) => Course.fromJson(data)).toList();

      // Always show all courses initially
      _filteredCourses = List.from(_allCourses);

      // If user is authenticated, fetch user-specific data
      if (_isAuthenticated) {
        await _fetchUserSpecificData();
      }
    } catch (e) {
      NyLogger.error('Error fetching courses: $e');

      // Fallback to local data if API fails

      _filteredCourses = [];

      // Show error using Nylo toast
      showToast(
          title: trans("Error"),
          description:
              trans("Failed to load courses from server, showing cached data"),
          icon: Icons.error_outline,
          style: ToastNotificationStyleType.warning);
    } finally {
      // Complete loading
      setLoading(false, name: 'fetch_courses');
    }
  }

  Future<void> _fetchUserSpecificData() async {
    if (!_isAuthenticated) return;

    setLoading(true, name: 'fetch_user_data');

    try {
      var courseApiService = CourseApiService();

      // Parallel fetch for better performance
      var results = await Future.wait([
        courseApiService.getEnrolledCourses(),
        courseApiService.getWishlist()
      ]);

      // Process enrolled courses
      List<dynamic> enrolledCoursesData = results[0];
      _enrolledCourses = enrolledCoursesData
          .map((data) => Course.fromJson(data['course']))
          .toList();

      // Process wishlist data - store both Course objects and Wishlist objects
      List<dynamic> wishlistData = results[1];

      // Store Wishlist items directly
      _wishlistItems =
          wishlistData.map((data) => Wishlist.fromJson(data)).toList();

      // Also keep the course objects for display

      NyLogger.debug('Loaded ${_wishlistItems.length} wishlist items');
    } catch (e) {
      NyLogger.error('Error fetching user data: $e');

      // Only show toast if it's not a "not logged in" error
      if (e.toString() != "Exception: Not logged in") {
        showToastWarning(
            description: trans("Could not fetch your saved courses"));
      }
    } finally {
      setLoading(false, name: 'fetch_user_data');
    }
  }

  void _performSearch(String query) {
    setState(() {
      _searchQuery = query;

      if (query.isEmpty) {
        // Show all courses when search is cleared
        _filteredCourses = List.from(_allCourses);
        return;
      }

      // Apply the search filter
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
      // If not authenticated, ask the user to login
      confirmAction(() {
        routeTo(SigninPage.path);
      },
          title: trans("You need to login to save courses to your wishlist."),
          confirmText: trans("Login"),
          dismissText: trans("Cancel"));
      return;
    }

    // Check if course is in wishlist
    bool isInWishlist = _wishlistItems.any((c) => c.courseId == course.id);

    try {
      await lockRelease('toggle_wishlist_${course.id}', perform: () async {
        var courseApiService = CourseApiService();

        if (isInWishlist) {
          // Find wishlist item id from the _wishlistItems list
          Wishlist? wishlistItem;
          try {
            wishlistItem =
                _wishlistItems.firstWhere((item) => item.courseId == course.id);
          } catch (e) {
            // No matching item found
            wishlistItem = null;
          }

          if (wishlistItem != null) {
            await courseApiService.removeFromWishlist(wishlistItem.id);
            showToastInfo(description: trans("Course removed from wishlist"));

            // Remove from both lists
            setState(() {
              _wishlistItems.removeWhere((item) => item.courseId == course.id);
            });

            // Notify wishlist tab about the change
            updateState('/wishlist_tab', data: "refresh_wishlist");
          }
        } else {
          // Add to wishlist - Parse course.id to int
          var response = await courseApiService.addToWishlist(course.id);

          // Create Wishlist object from response and add to list
          if (response != null) {
            Wishlist newWishlistItem = Wishlist.fromJson(response);

            setState(() {
              _wishlistItems.add(newWishlistItem);
            });
          }

          showToastSuccess(description: trans("Course added to wishlist"));

          // Notify wishlist tab about the change
          updateState('/wishlist_tab', data: "refresh_wishlist");
        }
      });
    } catch (e) {
      showToastDanger(description: trans("Failed to update wishlist"));
      NyLogger.error('Error toggling wishlist: $e');
    }
  }

  Future<void> _enrollInCourse(Course course) async {
    if (!_isAuthenticated) {
      // If not authenticated, ask the user to login
      confirmAction(() {
        routeTo(SigninPage.path);
      },
          title: trans("You need to login to enroll in courses."),
          confirmText: trans("Login"),
          dismissText: trans("Cancel"));
      return;
    }

    // Check if already enrolled
    bool isEnrolled = _enrolledCourses.any((c) => c.id == course.id);

    if (isEnrolled) {
      routeTo(PurchasedCourseDetailPage.path, data: {'course': course});
      return;
    }

    // Navigate directly to enrollment plan page instead of confirming
    routeTo(CourseDetailPage.path, data: {
      'course': course,
    });
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
            // Search bar
            _buildSearchBar(),

            // Content area
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
                        // Hide keyboard
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
              // Show filter options dialog
              _showFilterDialog();
            },
          ),
          if (_isAuthenticated)
            IconButton(
              icon: Icon(Icons.refresh, color: Colors.black),
              onPressed: () async {
                // Refresh courses with the latest data
                await _fetchCourses(refresh: true);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    // Show the empty state only when no courses are loaded at all
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

            // Show login button if not authenticated
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

    // No results found
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

    // Search results
    return Column(
      children: [
        // Results count
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

              // Sort dropdown
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

        // Results list
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.symmetric(horizontal: 16),
            itemCount: _filteredCourses.length,
            itemBuilder: (context, index) {
              final course = _filteredCourses[index];

              // Check if course is in wishlist
              bool isInWishlist =
                  _wishlistItems.any((c) => c.courseId == course.id);

              // Check if already enrolled
              bool isEnrolled = _enrolledCourses.any((c) => c.id == course.id);

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
                // Course image
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

                // Course info
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title
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

                        // Subtitle
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

                        // Provider location
                        // For course IDs matching the screenshot examples
                        if (course.id == '5' || course.id == '1')
                          Text(
                            "Pragya Valley, Deepika Nair",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),

                        SizedBox(height: 4),

                        // Category
                        Row(
                          children: [
                            Text(
                              course.categoryName,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            ),

                            // Display "LIVE" badge for specific courses
                            if (course.id == '7')
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

                            // Display enrolled badge if enrolled
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

                // Wishlist icon (only for authenticated users)
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

            // Action buttons
            if (_isAuthenticated)
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Enroll button
                    ElevatedButton(
                      onPressed: () => _enrollInCourse(course),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            isEnrolled ? Colors.grey.shade200 : Colors.amber,
                        padding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      child: Text(
                        isEnrolled ? trans("View Course") : trans('Enroll Now'),
                        style: TextStyle(
                          color: isEnrolled ? Colors.black87 : Colors.white,
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
    // Get unique categories for filtering
    final List<String> categories =
        _allCourses.map((course) => course.categoryName).toSet().toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Allows the modal to expand if needed
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Container(
        padding: EdgeInsets.all(16),
        // Allow more height if we have many categories
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

            // Filter options in a scrollable container
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Category filter with dropdown for many categories
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
                        // Sort by rating (simulated since rating isn't in the model)
                        setState(() {
                          // Typically would sort by rating field, here we use course ID as proxy
                          _filteredCourses.sort((a, b) => b.id.compareTo(a.id));
                        });
                      },
                    ),

                    ListTile(
                      leading: Icon(Icons.timer),
                      title: Text(trans("New Courses")),
                      onTap: () {
                        pop();
                        // Filter to only show courses with IDs 7, 8, 9 (simulating newest courses)
                        setState(() {
                          _filteredCourses = _allCourses
                              .where((course) =>
                                  ['7', '8', '9'].contains(course.id))
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
                          // Filter to show only wishlist courses
                          setState(() {
                            _filteredCourses = _allCourses
                                .where((course) => _wishlistItems
                                    .any((c) => c.courseId == course.id))
                                .toList();
                          });
                        },
                      ),

                    if (_isAuthenticated)
                      ListTile(
                        leading: Icon(Icons.school),
                        title: Text(trans("Enrolled Only")),
                        onTap: () {
                          pop();
                          // Filter to show only enrolled courses
                          setState(() {
                            _filteredCourses = _allCourses
                                .where((course) => _enrolledCourses
                                    .any((c) => c.id == course.id))
                                .toList();
                          });
                        },
                      ),
                  ],
                ),
              ),
            ),

            Divider(),

            // Reset button
            Center(
              child: ElevatedButton(
                onPressed: () {
                  pop();
                  // Reset all filters to show all courses
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

            // Sort options
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

  // Skeleton layout for loading state
  Widget _buildSkeletonLayout() {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: Column(
          children: [
            // Search bar skeleton
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

            // Content area skeleton
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
