import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:nylo_framework/nylo_framework.dart';

import '../../app/models/course.dart';
import '../../utils/course_data.dart';

class PurchasedCourseDetailPage extends NyStatefulWidget {
  static RouteView path =
      ("/purchased-course-detail", (_) => PurchasedCourseDetailPage());

  PurchasedCourseDetailPage({super.key})
      : super(child: () => _PurchasedCourseDetailPageState());
}

class _PurchasedCourseDetailPageState
    extends NyPage<PurchasedCourseDetailPage> {
  late Course _course;
  List<Map<String, dynamic>> _curriculumItems = [];
  int _currentLessonIndex = 0; // Track current lesson
  bool _isDownloaded = false;
  bool _isCertified = false;

  @override
  get init => () async {
        super.init();

        // Get course from widget.data()
        _course = widget.data()['course'];
        await _fetchCourseDetails();
      };

  Future<void> _fetchCourseDetails() async {
    setLoading(true);

    try {
      // Simulate API delay
      await Future.delayed(Duration(milliseconds: 800));

      // Fetch curriculum items
      _curriculumItems = CourseData.getCurriculumItems();

      // For demo purposes, mark some lessons as completed
      for (int i = 0; i < 3; i++) {
        _curriculumItems[i]['isCompleted'] = true;
      }

      // Check if course is downloaded (for demo purposes)
      _isDownloaded = _course.id == '1' || _course.id == '5';
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

  void _onStartLesson(int index) {
    setState(() {
      _currentLessonIndex = index;
    });

    // Navigate to video player or mark as completed for demo
    if (index > 0 && index < 3) {
      showToast(
          title: trans("Success"),
          description: trans("Lesson marked as completed"),
          icon: Icons.check_circle,
          style: ToastNotificationStyleType.success);

      setState(() {
        _curriculumItems[index]['isCompleted'] = true;
      });
    } else {
      // For demo, show that lesson is being played
      showBottomSheet(
        context: context,
        builder: (context) => Container(
          padding: EdgeInsets.all(16),
          height: 200,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                trans("Playing Lesson ${index + 1}"),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 20),
              Text(_curriculumItems[index]['title']),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() {
                    _curriculumItems[index]['isCompleted'] = true;
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                ),
                child: Text(trans("Mark as Completed")),
              ),
            ],
          ),
        ),
      );
    }
  }

  void _toggleDownload() {
    setState(() {
      _isDownloaded = !_isDownloaded;
    });

    if (_isDownloaded) {
      showToast(
          title: trans("Download Started"),
          description: trans("Course is being downloaded for offline viewing"),
          icon: Icons.download,
          style: ToastNotificationStyleType.info);
    } else {
      showToast(
          title: trans("Download Removed"),
          description: trans("Course has been removed from downloads"),
          icon: Icons.delete,
          style: ToastNotificationStyleType.warning);
    }
  }

  void _getCertificate() {
    setState(() {
      _isCertified = true;
    });

    showToast(
        title: trans("Congratulations!"),
        description: trans("Your certificate has been generated"),
        icon: Icons.workspace_premium,
        style: ToastNotificationStyleType.success);
  }

  @override
  Widget view(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Course Banner and Header
            _buildCourseHeader(),

            // Course Videos List
            Expanded(
              child: _buildCourseContent(),
            ),

            // Bottom Navigation
            _buildBottomNavigation(),
          ],
        ),
      ),
    );
  }

  Widget _buildCourseHeader() {
    return Stack(
      children: [
        // Banner Image with Gradient Overlay
        CachedNetworkImage(
          imageUrl: _course
              .image, // Use the image URL directly from your Course model
          imageBuilder: (context, imageProvider) => Container(
            height: 160,
            width: double.infinity,
            decoration: BoxDecoration(
              image: DecorationImage(
                image: imageProvider,
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  Colors.black.withOpacity(0.3),
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
                    Colors.green.withOpacity(0.9),
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
                ],
              ),
            ),
          ),
          placeholder: (context, url) => Container(
            height: 160,
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
            height: 160,
            width: double.infinity,
            color: Colors.grey[300],
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.green.withOpacity(0.9),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Center(
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      color: Colors.white70,
                      size: 40,
                    ),
                  ),
                ),
                Container(
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
          child: CircleAvatar(
            backgroundColor: Colors.white.withOpacity(0.7),
            radius: 16,
            child: IconButton(
              icon: Icon(Icons.arrow_back, size: 16, color: Colors.black),
              onPressed: () => Navigator.pop(context),
              padding: EdgeInsets.zero,
              constraints: BoxConstraints(),
            ),
          ),
        ),

        // Download Button
        Positioned(
          top: 8,
          right: 8,
          child: CircleAvatar(
            backgroundColor: Colors.white.withOpacity(0.7),
            radius: 16,
            child: IconButton(
              icon: Icon(
                _isDownloaded ? Icons.download_done : Icons.download_outlined,
                size: 16,
                color: _isDownloaded ? Colors.amber : Colors.black,
              ),
              onPressed: _toggleDownload,
              padding: EdgeInsets.zero,
              constraints: BoxConstraints(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCourseContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Course Title
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _course.title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 4),
              Text(
                _course.smallDesc,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),

        // Videos Section
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Videos",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                "15 hours • 25 videos total lesson",
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),

        // Curriculum List
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.only(top: 8, bottom: 16),
            itemCount: 25, // Using 25 lessons from the screenshot
            itemBuilder: (context, index) {
              // For indices beyond our demo data, create dummy items
              Map<String, dynamic> item = index < _curriculumItems.length
                  ? _curriculumItems[index]
                  : {
                      'id': index + 1,
                      'title': 'Class Introduction Video',
                      'duration': '${(index % 5) + 8}m',
                      'isCompleted': index < 3,
                    };

              bool isCompleted = item['isCompleted'] ?? false;
              bool isCurrent = _currentLessonIndex == index;

              return _buildLessonItem(
                index: index,
                title: item['title'],
                duration: item['duration'],
                isCompleted: isCompleted,
                isCurrent: isCurrent,
              );
            },
          ),
        ),

        // Certification Section
        Container(
          padding: EdgeInsets.all(16),
          color: Colors.grey.shade100,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Certification",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 8),
              Text(
                "Complete the curriculum to access your course certificate. You can continue from where you stopped.",
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                ),
              ),
              SizedBox(height: 12),
              Row(
                children: [
                  ElevatedButton(
                    onPressed: _isCertified ? null : _getCertificate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _isCertified ? Colors.grey.shade300 : Colors.amber,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      padding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    child: Text(
                      trans(_isCertified
                          ? "Certificate Issued"
                          : "Get Certificate"),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLessonItem({
    required int index,
    required String title,
    required String duration,
    required bool isCompleted,
    required bool isCurrent,
  }) {
    return InkWell(
      onTap: () => _onStartLesson(index),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Colors.grey.shade200,
              width: 1,
            ),
          ),
          color: isCurrent ? Colors.amber.withOpacity(0.1) : null,
        ),
        child: Row(
          children: [
            // Lesson Number
            Container(
              width: 24,
              child: Text(
                "${index + 1}",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isCompleted ? Colors.amber : Colors.black,
                ),
              ),
            ),

            // Lesson Title and Duration
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          isCompleted ? FontWeight.w600 : FontWeight.normal,
                      color: isCompleted ? Colors.amber : Colors.black,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    "video • $duration",
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),

            // Completed Icon or Download Icon
            if (isCompleted)
              Icon(Icons.check_circle, color: Colors.amber, size: 20)
            else
              Icon(Icons.download_outlined, color: Colors.grey, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavigation() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 4,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Class info
          Expanded(
            child: Row(
              children: [
                Icon(Icons.play_circle_outline, color: Colors.grey.shade700),
                SizedBox(width: 8),
                Text(
                  "Class Introduction Video",
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),

          // Continue Button
          ElevatedButton(
            onPressed: () => _onStartLesson(_currentLessonIndex),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: Text(
              trans("Continue"),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
