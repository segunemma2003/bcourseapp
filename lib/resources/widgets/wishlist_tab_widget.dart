import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/resources/pages/base_navigation_hub.dart';
import 'package:flutter_app/resources/pages/course_detail_page.dart';
import 'package:flutter_app/resources/pages/signin_page.dart';
import 'package:nylo_framework/nylo_framework.dart';

import '../../app/models/course.dart';
import '../../app/models/wishlist.dart';
import '../../app/networking/course_api_service.dart';

class WishlistTab extends StatefulWidget {
  const WishlistTab({super.key});

  // Define state name for Nylo's state management
  static String state = '/wishlist_tab';

  @override
  createState() => _WishlistTabState();
}

class _WishlistTabState extends NyState<WishlistTab> {
  // Store wishlist items directly
  List<Wishlist> _wishlistItems = [];
  bool _hasWishlistedCourses = false;
  bool _isAuthenticated = false;

  // Track loading state for each wishlist item's view details button
  Set<String> _loadingViewDetails = <String>{};

  // Set state name for Nylo's state management
  _WishlistTabState() {
    stateName = WishlistTab.state;
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

        // Fetch wishlisted courses
        await _fetchWishlistedCourses();
      };

  @override
  stateUpdated(data) async {
    if (data == "refresh_wishlist") {
      await _fetchWishlistedCourses(refresh: true);
    } else if (data == "update_auth_status") {
      setState(() {
        _isAuthenticated = true; // Update auth status
      });
      await _fetchWishlistedCourses(refresh: true);
    }

    return super.stateUpdated(data);
  }

  Future<void> _fetchWishlistedCourses({bool refresh = false}) async {
    NyLogger.debug('=== STARTING _fetchWishlistedCourses() in WishlistTab ===');
    NyLogger.debug('refresh parameter: $refresh');

    setLoading(true, name: 'fetch_wishlist');

    try {
      // If not authenticated, we can't fetch wishlisted courses
      if (!_isAuthenticated) {
        NyLogger.debug('User not authenticated, clearing wishlist');
        setState(() {
          _wishlistItems = [];
          _hasWishlistedCourses = false;
        });
        return;
      }

      // Use the CourseApiService to fetch wishlisted courses
      var courseApiService = CourseApiService();

      try {
        NyLogger.debug('Attempting to fetch wishlist from API');
        // Fetch wishlist from API
        List<dynamic> wishlistData =
            await courseApiService.getWishlist(refresh: refresh);

        NyLogger.debug(
            'Wishlist data fetched successfully, type: ${wishlistData.runtimeType}');
        NyLogger.debug('Wishlist data length: ${wishlistData.length}');

        // Store direct wishlist items
        if (wishlistData.isNotEmpty) {
          List<Wishlist> items = [];

          for (var item in wishlistData) {
            try {
              Wishlist wishlistItem = Wishlist.fromJson(item);
              items.add(wishlistItem);
              NyLogger.debug(
                  'Successfully added wishlist item for course: ${wishlistItem.courseTitle}');
            } catch (e) {
              NyLogger.error('Error processing wishlist item: $e');
              NyLogger.error('Problematic data: $item');
            }
          }

          setState(() {
            _wishlistItems = items;
            _hasWishlistedCourses = items.isNotEmpty;
          });

          NyLogger.debug('Set ${items.length} wishlist items to state');
        } else {
          NyLogger.debug('Wishlist is empty');
          setState(() {
            _wishlistItems = [];
            _hasWishlistedCourses = false;
          });
        }
      } catch (e) {
        // Error handling for API failures
        NyLogger.error('API Error: $e');

        setState(() {
          _wishlistItems = [];
          _hasWishlistedCourses = false;
        });

        showToast(
            title: trans("Error"),
            description: trans("Failed to load your wishlist"),
            icon: Icons.error_outline,
            style: ToastNotificationStyleType.danger);
      }
    } catch (e) {
      NyLogger.error('Unhandled exception in _fetchWishlistedCourses: $e');

      showToast(
          title: trans("Error"),
          description: trans("Failed to load your wishlist"),
          icon: Icons.error_outline,
          style: ToastNotificationStyleType.danger);

      // Reset state on error
      setState(() {
        _wishlistItems = [];
        _hasWishlistedCourses = false;
      });
    } finally {
      setLoading(false, name: 'fetch_wishlist');
      NyLogger.debug(
          '=== FINISHED _fetchWishlistedCourses() in WishlistTab ===');
    }
  }

  void _onGetStartedPressed() async {
    // Navigate to search tab (index 1 in BaseNavigationHub)
    routeTo(BaseNavigationHub.path, tabIndex: 1);
  }

  void _viewCourseDetails(Wishlist wishlistItem) async {
    // Use lockRelease to prevent multiple simultaneous clicks on the same item
    await lockRelease('view_course_details_${wishlistItem.id}',
        perform: () async {
      try {
        // Show loading indicator on button
        setState(() {
          _loadingViewDetails.add(wishlistItem.id.toString());
        });

        // Fetch the complete course details using the courseId
        var courseApiService = CourseApiService();

        // First try to get course details
        try {
          // Get the course data using courseId
          dynamic courseData =
              await courseApiService.getCourseDetails(wishlistItem.courseId);

          // Check if courseData is a List or a single object
          if (courseData is List) {
            // If it's a list, take the first item
            if (courseData.isNotEmpty) {
              // Convert the first item to a Course object
              Course course = Course.fromJson(courseData[0]);
              // Navigate to course detail with the course object
              routeTo(CourseDetailPage.path, data: {'course': course});
            } else {
              throw Exception("No course details returned");
            }
          } else {
            // If it's a single object, convert directly
            Course course = Course.fromJson(courseData);
            routeTo(CourseDetailPage.path, data: {'course': course});
          }
        } catch (e) {
          NyLogger.error('Failed to fetch course details: $e');

          // Try to get complete details with enrollment info if basic details fails
          try {
            var completeDetails = await courseApiService
                .getCompleteDetails(wishlistItem.courseId);

            // Check if completeDetails is a Course or needs conversion
            if (completeDetails is Course) {
              routeTo(CourseDetailPage.path, data: {'course': completeDetails});
            } else {
              Course course = Course.fromJson(completeDetails);
              routeTo(CourseDetailPage.path, data: {'course': course});
            }
          } catch (e2) {
            NyLogger.error('Both detail fetch attempts failed: $e2');

            // Show error toast
            showToastWarning(
              description:
                  trans("Could not load course details, please try again"),
            );

            // If getting course details fails, redirect to search tab to browse all courses
            confirmAction(() {
              routeTo(BaseNavigationHub.path, tabIndex: 1);
            },
                title: trans("Course details could not be loaded"),
                confirmText: trans("Browse Courses"),
                dismissText: trans("Cancel"));
          }
        }
      } catch (e) {
        NyLogger.error('Error navigating to course details: $e');
        showToastDanger(description: trans("Could not load course details"));
      } finally {
        // Remove loading indicator
        setState(() {
          _loadingViewDetails.remove(wishlistItem.id.toString());
        });
      }
    });
  }

  Future<void> _removeFromWishlist(Wishlist wishlistItem) async {
    print("remove_from_wishlist_${wishlistItem.id}");
    // Using Nylo's lockRelease to prevent multiple simultaneous operations
    await lockRelease('remove_from_wishlist_${wishlistItem.id}',
        perform: () async {
      try {
        var courseApiService = CourseApiService();

        // Remove directly using the wishlist item ID
        await courseApiService.removeFromWishlist(wishlistItem.id);

        // Update local state
        setState(() {
          _wishlistItems.removeWhere((item) => item.id == wishlistItem.id);
          _hasWishlistedCourses = _wishlistItems.isNotEmpty;
        });

        // Show confirmation toast
        showToastInfo(description: trans("Course removed from wishlist"));

        // Also notify search tab to refresh its wishlist status
        updateState('/search_tab', data: {
          'update_wishlist_status': true,
          'course_id': wishlistItem.courseId.toString(),
          'is_in_wishlist': false
        });
      } catch (e) {
        NyLogger.error('Failed to remove from wishlist: $e');
        showToastDanger(
            description: trans("Failed to remove course from wishlist"));
      }
    });
  }

  Future<void> _onRefresh() async {
    // Using Nylo's lockRelease to prevent multiple refreshes
    await lockRelease('refresh_wishlist', perform: () async {
      await _fetchWishlistedCourses(refresh: true);

      // Show success toast
      showToastSuccess(description: trans("Wishlist refreshed successfully"));
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
              trans("Wishlist"),
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
            loadingKey: 'fetch_wishlist',
            child: () => Column(
              children: [
                // Main Content
                Expanded(
                  child: _hasWishlistedCourses
                      ? _buildWishlistItems()
                      : (_isAuthenticated
                          ? _buildEmptyState()
                          : _buildLoginPrompt()),
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
                  Icons.favorite_border,
                  size: 80,
                  color: Colors.grey.shade400,
                ),
              );
            },
          ).localAsset(),

          SizedBox(height: 24),

          // Title
          Text(
            trans("Level up your fashion game"),
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
            trans("Save courses to your wishlist for later"),
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
            trans("Login to access your wishlist"),
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
            trans("Sign in to view your saved courses"),
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
                routeTo(SigninPage.path);
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

  Widget _buildWishlistItems() {
    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: _wishlistItems.length,
      itemBuilder: (context, index) {
        final wishlistItem = _wishlistItems[index];
        return _buildWishlistItem(wishlistItem);
      },
    );
  }

  Widget _buildWishlistItem(Wishlist wishlistItem) {
    final isLoadingViewDetails =
        _loadingViewDetails.contains(wishlistItem.id.toString());

    return Container(
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Course Image and Info
          InkWell(
            onTap: isLoadingViewDetails
                ? null
                : () => _viewCourseDetails(wishlistItem),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Course Image
                ClipRRect(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(8),
                    bottomLeft: Radius.circular(8),
                  ),
                  child: CachedNetworkImage(
                    imageUrl: wishlistItem.courseImage,
                    width: 140, // Increased width to make it rectangular
                    height: 100, // Keep height for rectangular shape
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      width: 140, // Increased width to make it rectangular
                      height: 100, // Keep height for rectangular shape
                      color: Colors.grey.shade300,
                      child: Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.0,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.amber),
                          ),
                        ),
                      ),
                    ),
                    errorWidget: (context, error, stackTrace) => Container(
                      width: 140, // Increased width to make it rectangular
                      height: 100, // Keep height for rectangular shape
                      color: Colors.grey.shade300,
                      child: Icon(
                        Icons.image_not_supported,
                        color: Colors.grey.shade700,
                      ),
                    ),
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
                          wishlistItem.courseTitle,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),

                        SizedBox(height: 4),

                        // Date Added
                        Text(
                          "Added on ${wishlistItem.dateAdded.split('T')[0]}",
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),

                        SizedBox(height: 8),

                        // Course ID badge
                        Container(
                          padding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            "Course #${wishlistItem.courseId}",
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Action buttons
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Remove from wishlist button
                TextButton.icon(
                  onPressed: () => _removeFromWishlist(wishlistItem),
                  icon: Icon(Icons.delete_outline,
                      size: 16, color: Colors.red.shade300),
                  label: Text(
                    trans("Remove"),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red.shade300,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                ),

                // View details button with loading state
                ElevatedButton(
                  onPressed: isLoadingViewDetails
                      ? null
                      : () => _viewCourseDetails(wishlistItem),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isLoadingViewDetails
                        ? Colors.grey.shade300
                        : Colors.amber,
                    foregroundColor: isLoadingViewDetails
                        ? Colors.grey.shade600
                        : Colors.black,
                    elevation: 0,
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isLoadingViewDetails) ...[
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.0,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.grey.shade600),
                          ),
                        ),
                        SizedBox(width: 8),
                      ],
                      Text(
                        isLoadingViewDetails
                            ? trans("Loading...")
                            : trans("View Details"),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
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
