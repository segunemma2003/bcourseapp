import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:nylo_framework/nylo_framework.dart';

import '../../app/models/course.dart';
import '../../utils/course_data.dart';

class CourseDetailWishlistPage extends NyStatefulWidget {
  static RouteView path =
      ("/course-detail-wishlist", (_) => CourseDetailWishlistPage());

  CourseDetailWishlistPage({super.key})
      : super(child: () => _CourseDetailWishlistPageState());
}

class _CourseDetailWishlistPageState extends NyPage<CourseDetailWishlistPage> {
  late Course _course;
  List<Map<String, dynamic>> _curriculumItems = [];
  List<String> _achievements = [];
  List<String> _requirements = [];
  bool _isInWishlist = true;
  bool _showAllCurriculum = false;

  @override
  get init => () async {
        // Get course from widget.data()
        _course = widget.data()['course'];
        await _fetchCourseDetails();
      };
  Future<void> _fetchCourseDetails() async {
    setLoading(true);

    try {
      // Fetch course curriculum
      _curriculumItems = CourseData.getCurriculumItems();

      // Fetch achievements and requirements
      _achievements = CourseData.getAchievements();
      _requirements = CourseData.getRequirements();

      // Check if course is in wishlist
      List<String>? wishlistIds = await NyStorage.read('wishlisted_course_ids');
      _isInWishlist = wishlistIds != null && wishlistIds.contains(_course.id);
    } catch (e) {
      NyLogger.error('Failed to fetch course details: $e');

      showToast(
          title: trans("Error"),
          description: trans("Failed to load course details"),
          icon: Icons.error_outline,
          style: ToastNotificationStyleType.danger);
    } finally {
      setLoading(false);
    }
  }

  void _toggleWishlist() async {
    List<String> wishlistIds = [];
    List<String>? existingIds = await NyStorage.read('wishlisted_course_ids');

    if (existingIds != null) {
      wishlistIds = List<String>.from(existingIds);
    }

    setState(() {
      _isInWishlist = !_isInWishlist;
    });

    if (_isInWishlist) {
      if (!wishlistIds.contains(_course.id)) {
        wishlistIds.add(_course.id.toString());
      }
      showToast(
          title: trans("Added to Wishlist"),
          description: trans("Course has been added to your wishlist"),
          icon: Icons.check_circle,
          style: ToastNotificationStyleType.success);
    } else {
      wishlistIds.removeWhere((id) => id == _course.id);
      showToast(
          title: trans("Removed from Wishlist"),
          description: trans("Course has been removed from your wishlist"),
          icon: Icons.info,
          style: ToastNotificationStyleType.info);
    }

    // await NyStorage.store('wishlisted_course_ids', wishlistIds);
  }

  void _enrollNow() {
    showToast(
        title: trans("Enrollment Started"),
        description: trans("Processing your enrollment"),
        icon: Icons.school,
        style: ToastNotificationStyleType.success);

    // In a real app, this would navigate to a payment page
    // or directly enroll the user if the course is free
  }

  void _toggleShowAllCurriculum() {
    setState(() {
      _showAllCurriculum = !_showAllCurriculum;
    });
  }

  @override
  Widget view(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Course Banner and Header
              _buildCourseHeader(),

              // Course Title and Description
              _buildCourseInfo(),

              // What You'll Achieve Section
              _buildAchievementsSection(),

              // Course Curriculum Section
              _buildCurriculumSection(),

              // Requirements Section
              _buildRequirementsSection(),

              // Price and Enrollment Section
              _buildPriceSection(),

              // Bottom Padding
              SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCourseHeader() {
    return Stack(
      children: [
        // Course Banner
        CachedNetworkImage(
          imageUrl: _course.image, // Use the image URL from your Course model
          imageBuilder: (context, imageProvider) => Container(
            height: 180,
            width: double.infinity,
            decoration: BoxDecoration(
              image: DecorationImage(
                image: imageProvider,
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  Colors.black.withValues(alpha: 0.3),
                  BlendMode.darken,
                ),
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.green.withValues(alpha: .9),
                  ],
                ),
              ),
              padding: EdgeInsets.all(16),
              alignment: Alignment.bottomLeft,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "BOUTIQUE START\nUP COURSE",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "ONE-MONTH\nONLINE COURSE",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: 8),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.amber,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      "ENROLL",
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          placeholder: (context, url) => Container(
            height: 180,
            width: double.infinity,
            color: Colors.grey[300],
            child: Center(
              child: CircularProgressIndicator(
                valueColor:
                    AlwaysStoppedAnimation<Color>(const Color(0xFFFFEB3B)),
              ),
            ),
          ),
          errorWidget: (context, url, error) => Container(
            height: 180,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.grey[400]!,
                  Colors.green.withValues(alpha: .9),
                ],
              ),
            ),
            padding: EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.image_not_supported_outlined,
                  color: Colors.white70,
                  size: 40,
                ),
                SizedBox(height: 8),
                Text(
                  'Image not available',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                  ),
                ),
                Spacer(),
                // Keep the original content even in error state
                Align(
                  alignment: Alignment.bottomLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "BOUTIQUE START\nUP COURSE",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          height: 1.2,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        "ONE-MONTH\nONLINE COURSE",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 8),
                      Container(
                        padding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.amber,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          "ENROLL",
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // Back Button
        Positioned(
          top: 8,
          left: 8,
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.7),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.arrow_back, size: 20),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCourseInfo() {
    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Course Title
          Text(
            _course.title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),

          SizedBox(height: 4),

          // Course Subtitle in Hindi
          Text(
            _course.smallDesc,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
            ),
          ),

          SizedBox(height: 16),

          // Course Description
          Text(
            _course.smallDesc,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade800,
              height: 1.5,
            ),
          ),

          SizedBox(height: 16),

          // Course Details in Rows
          Row(
            children: [
              Icon(Icons.calendar_today, size: 16, color: Colors.grey),
              SizedBox(width: 8),
              Text(
                "Updated ${_course.dateUploaded}",
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),

          SizedBox(height: 8),

          Row(
            children: [
              Icon(Icons.person, size: 16, color: Colors.grey),
              SizedBox(width: 8),
              Text(
                "${_course.enrolledStudents}",
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAchievementsSection() {
    return Container(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "What you'll achieve after the course",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),

          SizedBox(height: 16),

          // Achievements List
          ..._achievements
              .map((achievement) => _buildAchievementItem(achievement))
              .toList(),
        ],
      ),
    );
  }

  Widget _buildAchievementItem(String achievement) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: EdgeInsets.only(top: 4),
            padding: EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.amber, width: 2),
            ),
            child: Icon(Icons.check, size: 12, color: Colors.amber),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              achievement,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade800,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurriculumSection() {
    // Determine how many items to show
    int itemsToShow = _showAllCurriculum ? _curriculumItems.length : 5;
    List<Map<String, dynamic>> displayItems =
        _curriculumItems.take(itemsToShow).toList();

    return Container(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Course Curriculum",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),

          SizedBox(height: 8),

          Row(
            children: [
              Text(
                "${_curriculumItems.length} videos • ",
                // ${_course.duration}
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),

          SizedBox(height: 16),

          // Curriculum Items
          ...displayItems.map((item) => _buildCurriculumItem(item)).toList(),

          // Show All / See Less Button
          if (_curriculumItems.length > 5)
            TextButton(
              onPressed: _toggleShowAllCurriculum,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _showAllCurriculum ? "See less videos" : "See all videos",
                    style: TextStyle(
                      color: Colors.amber,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Icon(
                    _showAllCurriculum
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: Colors.amber,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCurriculumItem(Map<String, dynamic> item) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Row(
        children: [
          Text(
            "${item['id']}",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['title'],
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey.shade100,
            ),
            child: Icon(
              Icons.play_arrow,
              size: 16,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequirementsSection() {
    return Container(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Requirements",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),

          SizedBox(height: 16),

          // Requirements List
          ..._requirements
              .map((requirement) => _buildRequirementItem(requirement))
              .toList(),
        ],
      ),
    );
  }

  Widget _buildRequirementItem(String requirement) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: EdgeInsets.only(top: 4),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey.shade700,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              requirement,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade800,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceSection() {
    return Container(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                "",
                // _course.price,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          SizedBox(height: 16),

          // Enroll Now Button
          Container(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _enrollNow,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
                padding: EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: Text(
                "Enroll Now",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),

          SizedBox(height: 16),

          // Remove from Wishlist Button
          Container(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _toggleWishlist,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black,
                side: BorderSide(color: Colors.grey.shade300),
                padding: EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: Text(
                _isInWishlist ? "Remove from Wishlist" : "Add to Wishlist",
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
