import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/resources/pages/course_curriculum_page.dart';
import 'package:nylo_framework/nylo_framework.dart';

import '../../app/models/course.dart';
import '../../app/networking/course_api_service.dart';
import '../../app/services/video_service.dart';
import '../../utils/course_data.dart';
import '../widgets/courses_tab_widget.dart';

class PurchasedCourseDetailPage extends NyStatefulWidget {
  static RouteView path =
      ("/purchased-course-detail", (_) => PurchasedCourseDetailPage());

  PurchasedCourseDetailPage({super.key})
      : super(child: () => _PurchasedCourseDetailPageState());
}

class _PurchasedCourseDetailPageState
    extends NyPage<PurchasedCourseDetailPage> {
  late Course _course;
  List<dynamic> _curriculumItems = [];
  int _currentLessonIndex = 0; // Track current lesson
  bool _isDownloaded = false;

  // Video service to track downloads and playback
  final VideoService _videoService = VideoService();
  final CourseApiService _courseApiService = CourseApiService();
  // Track lesson progress
  Map<int, bool> _completedLessons = {};
  List<dynamic> objectives = [];
  List<dynamic> requirements = [];
  int _totalLessons = 0;
  int _completedLessonsCount = 0;
  String _totalDuration = "- minutes";
  double _courseProgress = 0.0;

  // Track downloaded videos
  Map<int, bool> _downloadedVideos = {};

  @override
  get init => () async {
        super.init();

        // Get course from widget.data()
        _course = widget.data()['course'];

        // Get saved progress from storage if any
        await _loadSavedProgress();

        // Fetch curriculum items
        await _fetchCourseDetails(_course);
      };

  Future<void> _loadSavedProgress() async {
    try {
      // Load saved progress from NyStorage
      String key = 'course_progress_${_course.id}';
      Map<String, dynamic>? savedProgress = await NyStorage.read(key);

      if (savedProgress != null) {
        setState(() {
          // Convert the saved progress map to our format
          _completedLessons =
              Map<int, bool>.from(savedProgress['completedLessons'] ?? {});

          // Resume from last watched lesson
          _currentLessonIndex = savedProgress['currentLesson'] ?? 0;
        });
      }
    } catch (e) {
      NyLogger.error('Failed to load saved progress: $e');
    }
  }

  Future<void> _loadCourseCurriculum(int courseId) async {
    try {
      _curriculumItems = await _courseApiService.getCourseCurriculum(courseId);
      // Sort by order field
      _curriculumItems.sort((a, b) => a['order'].compareTo(b['order']));
    } catch (e) {
      print('Error loading curriculum: $e');
      // Set empty list on error
      _curriculumItems = [];
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

  Future<void> _fetchCourseDetails(course) async {
    setLoading(true);

    try {
      // Simulate API delay
      await Future.delayed(Duration(milliseconds: 800));

      // Fetch curriculum items - this would normally come from an API
      // Here we use the local data, but in a real app this would come from the server
      int courseId = course!.id;
      await _loadCourseCurriculum(courseId).catchError((e) {
        print('Error loading curriculum: $e');
        // Set empty list on error
        _curriculumItems = [];
      });

      if (mounted) {
        setLoading(false, name: 'curriculum');
        // Calculate total duration once curriculum is loaded
        _calculateTotalDuration();
      }

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

      // _curriculumItems = CourseData.getCurriculumItems();
      // _totalLessons = _curriculumItems.length;

      // Check if videos are downloaded
      await _checkDownloadedVideos();

      // Calculate course progress
      _updateCourseProgress();
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

  void _calculateTotalDuration() {
    try {
      int totalSeconds = 0;
      for (var item in _curriculumItems) {
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

  Future<void> _checkDownloadedVideos() async {
    // Check which videos are downloaded using the VideoService
    for (int i = 0; i < _curriculumItems.length; i++) {
      var item = _curriculumItems[i];

      if (item.containsKey('video_url') && item['video_url'] != null) {
        final String courseIdStr = _course.id.toString();
        final String videoIdStr = i.toString();

        // Check if already downloaded
        bool isDownloaded = await _videoService.isVideoDownloaded(
          videoUrl: item['video_url'],
          courseId: courseIdStr,
          videoId: videoIdStr,
        );

        // Check if currently downloading or watermarking
        bool isDownloading =
            _videoService.isDownloading(courseIdStr, videoIdStr);
        bool isWatermarking =
            _videoService.isWatermarking(courseIdStr, videoIdStr);

        // Check if queued
        bool isQueued = _videoService.isQueued(courseIdStr, videoIdStr);

        setState(() {
          // Only consider as downloaded if not in any other state
          _downloadedVideos[i] =
              isDownloaded && !isDownloading && !isWatermarking && !isQueued;
        });
      }
    }

    // Course is considered downloaded if at least one video is downloaded
    setState(() {
      _isDownloaded = _downloadedVideos.values.any((downloaded) => downloaded);
    });
  }

  void _updateCourseProgress() {
    // Count completed lessons
    _completedLessonsCount =
        _completedLessons.values.where((completed) => completed).length;

    // Calculate percentage completed
    _courseProgress =
        _totalLessons > 0 ? _completedLessonsCount / _totalLessons : 0.0;

    // Save progress
    _saveProgress();
  }

  Future<void> _saveProgress() async {
    try {
      String key = 'course_progress_${_course.id}';
      await NyStorage.save(key, {
        'completedLessons': _completedLessons,
        'currentLesson': _currentLessonIndex,
        'lastUpdated': DateTime.now().toIso8601String(),
      });

      // Also update in CoursesTab to reflect the progress
      updateState(CoursesTab.state, data: "update_course_progress");
    } catch (e) {
      NyLogger.error('Failed to save progress: $e');
    }
  }

  void _onStartLesson(int index) {
    setState(() {
      _currentLessonIndex = index;
    });

    // Check if the video is downloaded
    bool isDownloaded = _downloadedVideos[index] ?? false;

    if (isDownloaded) {
      // Play the video using VideoService
      _playVideo(index);
    } else {
      // Navigate to curriculum page for download/management
      _navigateToCurriculumPage(index);
    }
  }

  Future<void> _playVideo(int index) async {
    if (index >= _curriculumItems.length) return;

    var item = _curriculumItems[index];

    try {
      // Play the video using VideoService
      Future<void> played = _videoService.playVideo(
        videoUrl: item['video_url'],
        courseId: _course.id.toString(),
        videoId: index.toString(),
        watermarkText: "User", // This would come from user profile
        context: context,
      );

      // Mark as completed after watching
      setState(() {
        _completedLessons[index] = true;
        _updateCourseProgress();
      });

      // showToast(
      //     title: trans("Success"),
      //     description: trans("Lesson marked as completed"),
      //     icon: Icons.check_circle,
      //     style: ToastNotificationStyleType.success);
    } catch (e) {
      NyLogger.error('Failed to play video: $e');
      showToast(
          title: trans("Error"),
          description: trans("Failed to play video"),
          icon: Icons.error,
          style: ToastNotificationStyleType.danger);
    }
  }

  void _navigateToCurriculumPage(int startIndex) {
    // Navigate to curriculum page with current course and curriculum data
    routeTo(CourseCurriculumPage.path, data: {
      'course': _course,
      'curriculum': _curriculumItems,
      'startIndex': startIndex,
    }).then((_) {
      // Refresh downloaded status when returning from curriculum page
      _checkDownloadedVideos();
    });
  }

  void _toggleDownload() async {
    // If videos are already downloading, navigate to curriculum page to manage downloads
    if (_curriculumItems.isEmpty) {
      showToast(
        title: trans("No Content"),
        description: trans("No videos available to download"),
        icon: Icons.warning,
        style: ToastNotificationStyleType.warning,
      );
      return;
    }

    // Count existing downloaded videos
    int downloadedCount =
        _downloadedVideos.values.where((downloaded) => downloaded).length;

    // Check if any videos are currently downloading or watermarking
    bool isAnyProcessing = false;
    for (int i = 0; i < _curriculumItems.length; i++) {
      final String courseIdStr = _course.id.toString();
      final String videoIdStr = i.toString();

      if (_videoService.isDownloading(courseIdStr, videoIdStr) ||
          _videoService.isWatermarking(courseIdStr, videoIdStr) ||
          _videoService.isQueued(courseIdStr, videoIdStr)) {
        isAnyProcessing = true;
        break;
      }
    }

    // If any videos are downloading or all videos are already downloaded, go to curriculum page
    if (isAnyProcessing || downloadedCount == _curriculumItems.length) {
      _navigateToCurriculumPage(0);
      return;
    }

    // If no videos are downloading/queued and there are videos to download, show download all dialog
    bool confirm = await showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text(trans("Download All Videos")),
              content: Text(trans(
                  "Do you want to download all videos for offline viewing? This may use a significant amount of storage and data.")),
              actions: [
                TextButton(
                  child: Text(trans("Cancel")),
                  onPressed: () {
                    Navigator.of(context).pop(false);
                  },
                ),
                TextButton(
                  child: Text(trans("Download All")),
                  style: TextButton.styleFrom(foregroundColor: Colors.amber),
                  onPressed: () {
                    Navigator.of(context).pop(true);
                  },
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirm) return;

    try {
      // Get username for watermarking
      String username = "User";
      String email = "";
      try {
        var user = await Auth.data();
        if (user != null) {
          username = user['full_name']() ?? "User";
          email = user['email'] ?? "";
        }
      } catch (e) {
        NyLogger.error('Error getting username: $e');
      }

      // Use the batch download method in VideoService
      bool success = await _videoService.downloadAllVideos(
        courseId: _course.id.toString(),
        course: _course,
        curriculum: _curriculumItems,
        watermarkText: username,
        email: email,
      );

      if (success) {
        // Show success message
        showToast(
          title: trans("Success"),
          description: trans(
              "Videos are queued for download. You can continue using the app while downloads complete in the background."),
          icon: Icons.check_circle,
          style: ToastNotificationStyleType.success,
          duration: Duration(seconds: 4),
        );

        // Wait a moment then refresh status
        Future.delayed(Duration(seconds: 1), () {
          _checkDownloadedVideos();
        });
      } else {
        showToast(
          title: trans("Note"),
          description: trans("No new videos to download"),
          icon: Icons.info,
          style: ToastNotificationStyleType.info,
        );
      }
    } catch (e) {
      showToast(
        title: trans("Error"),
        description: trans("Failed to queue downloads"),
        icon: Icons.error,
        style: ToastNotificationStyleType.danger,
      );
    }
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
          imageUrl: _course.image,
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
                    _course.title.toUpperCase(),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    _course.smallDesc.toUpperCase(),
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
                        _course.title.toUpperCase(),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          height: 1.2,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        _course.smallDesc.toUpperCase(),
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
        // Course Title and Progress
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _course.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    "${(_courseProgress * 100).toInt()}% ${trans("Complete")}",
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.amber,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              SizedBox(height: .0),
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: _courseProgress,
                  backgroundColor: Colors.grey.shade200,
                  color: Colors.amber,
                  minHeight: 4,
                ),
              ),
              SizedBox(height: 8),
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
                "${_totalLessons} videos total",
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
            itemCount: _curriculumItems.length,
            itemBuilder: (context, index) {
              Map<String, dynamic> item = _curriculumItems[index];

              bool isCompleted = _completedLessons[index] ?? false;
              bool isDownloaded = _downloadedVideos[index] ?? false;
              bool isCurrent = _currentLessonIndex == index;

              return _buildLessonItem(
                index: index,
                title: item['title'] ?? 'Lesson ${index + 1}',
                duration: item['duration'] ?? '${(index % 5) + 8}m',
                isCompleted: isCompleted,
                isCurrent: isCurrent,
                isDownloaded: isDownloaded,
              );
            },
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
    required bool isDownloaded,
  }) {
    // Check download status from VideoService
    final String courseIdStr = _course.id.toString();
    final String videoIdStr = index.toString();

    bool isDownloading = _videoService.isDownloading(courseIdStr, videoIdStr);
    bool isWatermarking = _videoService.isWatermarking(courseIdStr, videoIdStr);
    bool isQueued = _videoService.isQueued(courseIdStr, videoIdStr);
    double progress = _videoService.getProgress(courseIdStr, videoIdStr);

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
                  // Show download progress if downloading
                  if (isDownloading || isWatermarking)
                    Container(
                      margin: EdgeInsets.only(top: 4),
                      height: 2,
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.grey[300],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isWatermarking ? Colors.orange : Colors.amber,
                        ),
                      ),
                    ),
                  // Show queued indicator
                  if (isQueued)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 4,
                            height: 4,
                            margin: EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                              color: Colors.amber,
                              shape: BoxShape.circle,
                            ),
                          ),
                          Text(
                            trans("Queued"),
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.amber,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // Status Icons
            if (isCompleted)
              Icon(Icons.check_circle, color: Colors.amber, size: 20)
            else if (isDownloading || isWatermarking)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: progress,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isWatermarking ? Colors.orange : Colors.amber,
                  ),
                ),
              )
            else if (isQueued)
              Icon(Icons.hourglass_bottom,
                  color: Colors.amber.withOpacity(0.7), size: 20)
            else if (isDownloaded)
              Icon(Icons.play_circle_outline, color: Colors.amber, size: 20)
            else
              Icon(Icons.download_outlined, color: Colors.grey, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavigation() {
    String nextLessonTitle = "Continue Learning";

    // Find the next incomplete lesson
    int nextLessonIndex = _currentLessonIndex;
    for (int i = 0; i < _curriculumItems.length; i++) {
      if (!(_completedLessons[i] ?? false)) {
        nextLessonIndex = i;
        if (i >= _currentLessonIndex) break;
      }
    }

    // Get title of the next lesson
    if (nextLessonIndex < _curriculumItems.length) {
      nextLessonTitle =
          _curriculumItems[nextLessonIndex]['title'] ?? "Continue Learning";
    }

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
                Expanded(
                  child: Text(
                    nextLessonTitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // Continue Button
          ElevatedButton(
            onPressed: () => _onStartLesson(nextLessonIndex),
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
              _courseProgress > 0 ? trans("Continue") : trans("Start Learning"),
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
