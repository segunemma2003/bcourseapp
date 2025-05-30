import 'package:flutter/material.dart';
import 'package:flutter_app/resources/pages/course_detail_page.dart';
import 'package:flutter_app/resources/pages/purchased_course_detail_page.dart';
import 'package:flutter_app/resources/pages/signin_page.dart';
import 'package:nylo_framework/nylo_framework.dart';

import '../../app/models/course.dart';
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
  // ✅ Removed _enrolledCourses list since we'll use Course.isEnrolled

  List<Wishlist> _wishlistItems = [];
  Map<String, dynamic>? _userData;
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
  get init => () async {
        super.init();

        _isAuthenticated = await Auth.isAuthenticated();
        if (_isAuthenticated) {
          _userData = await Auth.data();
        }

        await _fetchCourses();
        // ✅ Removed _fetchEnrolledCourses() call since enrollment status comes with courses

        _searchController.addListener(() {
          if (_searchController.text != _searchQuery) {
            _performSearch(_searchController.text);
          }
        });
      };

  // ✅ Removed _fetchEnrolledCourses method entirely

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
        "course_enrolled": (Map<String, dynamic> data) async {
          if (data.containsKey('updatedCourse') &&
              data.containsKey('courseId')) {
            try {
              Course updatedCourse = Course.fromJson(data['updatedCourse']);
              String courseId = data['courseId'].toString();

              // Find and update the course in our lists
              setState(() {
                // Update in _allCourses
                int allCoursesIndex =
                    _allCourses.indexWhere((c) => c.id.toString() == courseId);
                if (allCoursesIndex >= 0) {
                  _allCourses[allCoursesIndex] = updatedCourse;
                }

                // Update in _filteredCourses
                int filteredIndex = _filteredCourses
                    .indexWhere((c) => c.id.toString() == courseId);
                if (filteredIndex >= 0) {
                  _filteredCourses[filteredIndex] = updatedCourse;
                }
              });

              NyLogger.info(
                  'Updated course enrollment status in SearchTab for course $courseId');
            } catch (e) {
              NyLogger.error('Error updating course enrollment status: $e');
              // Fallback: refresh all courses
              await _fetchCourses(refresh: true);
            }
          }
        },
      };

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

      // ✅ Courses now come with isEnrolled field already populated
      _allCourses = coursesData.map((data) => Course.fromJson(data)).toList();
      _filteredCourses = List.from(_allCourses);

      if (_isAuthenticated) {
        // ✅ Only fetch wishlist data since enrollment status comes with courses
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

  // ✅ Simplified method to only fetch wishlist data
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

  // ✅ Renamed from _fetchUserSpecificData for clarity
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

    // ✅ Use course.isEnrolled instead of checking _enrolledCourses list
    if (course.isEnrolled) {
      routeTo(PurchasedCourseDetailPage.path, data: {'course': course});
      return;
    }

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
                await _fetchCourses(refresh: true);
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

              // ✅ Use course.isEnrolled directly
              bool isEnrolled = course.isEnrolled;

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
                            Text(
                              course.categoryName,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
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

                    // ✅ Updated to use course.isEnrolled
                    if (_isAuthenticated)
                      ListTile(
                        leading: Icon(Icons.school),
                        title: Text(trans("Enrolled Only")),
                        onTap: () {
                          pop();
                          setState(() {
                            _filteredCourses = _allCourses
                                .where((course) => course.isEnrolled)
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
