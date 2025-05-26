import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/resources/pages/course_curriculum_page.dart';
import 'package:flutter_app/resources/pages/enrollment_plan_page.dart';
import 'package:intl/intl.dart';
import 'package:nylo_framework/nylo_framework.dart';

import '../../app/models/course.dart';
import '../../app/models/enrollment.dart';
import '../../app/networking/course_api_service.dart';
import '../../app/services/video_service.dart';
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
  int _currentLessonIndex = 0;
  bool _isDownloaded = false;

  bool _hasValidSubscription = true;
  bool _isEnrolled = true;

  final VideoService _videoService = VideoService();
  final CourseApiService _courseApiService = CourseApiService();

  Map<int, bool> _completedLessons = {};
  List<dynamic> objectives = [];
  List<dynamic> requirements = [];
  int _totalLessons = 0;
  int _completedLessonsCount = 0;
  String _totalDuration = "- minutes";
  double _courseProgress = 0.0;

  Map<int, bool> _downloadedVideos = {};

  @override
  get init => () async {
        super.init();

        Map<String, dynamic> data = widget.data();
        _course = data['course'];

        // Get curriculum from passed data if available
        if (data.containsKey('curriculum') && data['curriculum'] != null) {
          _curriculumItems = List<dynamic>.from(data['curriculum']);
          _totalLessons = _curriculumItems.length;
          _calculateTotalDuration();
        } else {
          // Only fetch if not provided
          await _fetchCourseDetails(_course);
        }

        // Get objectives and requirements from passed data if available
        if (data.containsKey('objectives') && data['objectives'] != null) {
          objectives = List<dynamic>.from(data['objectives']);
        }

        if (data.containsKey('requirements') && data['requirements'] != null) {
          requirements = List<dynamic>.from(data['requirements']);
        }

        await _loadSavedProgress();
        await _checkSubscriptionStatus();
        await _checkDownloadedVideos();
      };

  Future<void> _checkSubscriptionStatus() async {
    try {
      bool isValid =
          await _courseApiService.checkEnrollmentValidity(_course.id);
      setState(() {
        _hasValidSubscription = isValid;
      });
    } catch (e) {
      NyLogger.error('Error checking subscription status: $e');
    }
  }

  Future<void> _loadSavedProgress() async {
    try {
      String key = 'course_progress_${_course.id}';
      Map<String, dynamic>? savedProgress = await NyStorage.read(key);

      if (savedProgress != null) {
        setState(() {
          _completedLessons =
              Map<int, bool>.from(savedProgress['completedLessons'] ?? {});
          _currentLessonIndex = savedProgress['currentLesson'] ?? 0;
        });
      }
    } catch (e) {
      NyLogger.error('Failed to load saved progress: $e');
    }
  }

  Future<void> _fetchCourseDetails(Course course) async {
    setLoading(true);

    try {
      await Future.delayed(Duration(milliseconds: 800));

      int courseId = course.id;

      // Fetch curriculum only if not already provided
      if (_curriculumItems.isEmpty) {
        await _loadCourseCurriculum(courseId).catchError((e) {
          print('Error loading curriculum: $e');
          _curriculumItems = [];
        });
      }

      if (mounted) {
        setLoading(false, name: 'curriculum');
        _calculateTotalDuration();
      }

      // Fetch objectives only if not already provided
      if (objectives.isEmpty) {
        await _loadCourseObjectives(courseId).catchError((e) {
          print('Error loading objectives: $e');
          objectives = [];
        });
      }

      if (mounted) {
        setLoading(false, name: 'objectives');
      }

      // Fetch requirements only if not already provided
      if (requirements.isEmpty) {
        await _loadCourseRequirements(courseId).catchError((e) {
          print('Error loading requirements: $e');
          requirements = [];
        });
      }

      if (mounted) {
        setLoading(false, name: 'requirements');
      }

      _totalLessons = _curriculumItems.length;
      await _checkDownloadedVideos();
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

  Future<void> _loadCourseCurriculum(int courseId) async {
    try {
      _curriculumItems = await _courseApiService.getCourseCurriculum(courseId);
      _curriculumItems.sort((a, b) => a['order'].compareTo(b['order']));
    } catch (e) {
      print('Error loading curriculum: $e');
      _curriculumItems = [];
      rethrow;
    }
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
              print('Error parsing duration: $e');
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
      print('Error calculating total duration: $e');
      setState(() {
        _totalDuration = "- minutes";
      });
    }
  }

  Future<void> _checkDownloadedVideos() async {
    for (int i = 0; i < _curriculumItems.length; i++) {
      var item = _curriculumItems[i];

      if (item.containsKey('video_url') && item['video_url'] != null) {
        final String courseIdStr = _course.id.toString();
        final String videoIdStr = i.toString();

        bool isDownloaded = await _videoService.isVideoDownloaded(
          videoUrl: item['video_url'],
          courseId: courseIdStr,
          videoId: videoIdStr,
        );

        bool isDownloading =
            _videoService.isDownloading(courseIdStr, videoIdStr);
        bool isWatermarking =
            _videoService.isWatermarking(courseIdStr, videoIdStr);
        bool isQueued = _videoService.isQueued(courseIdStr, videoIdStr);

        setState(() {
          _downloadedVideos[i] =
              isDownloaded && !isDownloading && !isWatermarking && !isQueued;
        });
      }
    }

    setState(() {
      _isDownloaded = _downloadedVideos.values.any((downloaded) => downloaded);
    });
  }

  void _updateCourseProgress() {
    _completedLessonsCount =
        _completedLessons.values.where((completed) => completed).length;

    _courseProgress =
        _totalLessons > 0 ? _completedLessonsCount / _totalLessons : 0.0;

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

      updateState(CoursesTab.state, data: "update_course_progress");
    } catch (e) {
      NyLogger.error('Failed to save progress: $e');
    }
  }

  void _onStartLesson(int index) {
    setState(() {
      _currentLessonIndex = index;
    });

    bool isDownloaded = _downloadedVideos[index] ?? false;

    if (isDownloaded) {
      _playVideo(index);
    } else {
      _navigateToCurriculumPage(index);
    }
  }

  Future<void> _playVideo(int index) async {
    if (index >= _curriculumItems.length) return;

    var item = _curriculumItems[index];

    try {
      await _videoService.playVideo(
        videoUrl: item['video_url'],
        courseId: _course.id.toString(),
        videoId: index.toString(),
        watermarkText: "User",
        context: context,
      );

      setState(() {
        _completedLessons[index] = true;
        _updateCourseProgress();
      });
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
    // Pass all available data to avoid API calls
    routeTo(CourseCurriculumPage.path, data: {
      'course': _course,
      'curriculum': _curriculumItems,
      'objectives': objectives,
      'requirements': requirements,
      'startIndex': startIndex,
    }).then((_) {
      _checkDownloadedVideos();
    });
  }

  void _toggleDownload() async {
    if (_curriculumItems.isEmpty) {
      showToast(
        title: trans("No Content"),
        description: trans("No videos available to download"),
        icon: Icons.warning,
        style: ToastNotificationStyleType.warning,
      );
      return;
    }

    int downloadedCount =
        _downloadedVideos.values.where((downloaded) => downloaded).length;

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

    if (isAnyProcessing || downloadedCount == _curriculumItems.length) {
      _navigateToCurriculumPage(0);
      return;
    }

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
      String username = "User";
      String email = "";
      try {
        var user = await Auth.data();
        if (user != null) {
          username = user['full_name'] ?? "User";
          email = user['email'] ?? "";
        }
      } catch (e) {
        NyLogger.error('Error getting username: $e');
      }

      bool success = await _videoService.downloadAllVideos(
        courseId: _course.id.toString(),
        course: _course,
        curriculum: _curriculumItems,
        watermarkText: username,
        email: email,
      );

      if (success) {
        showToast(
          title: trans("Success"),
          description: trans(
              "Videos are queued for download. You can continue using the app while downloads complete in the background."),
          icon: Icons.check_circle,
          style: ToastNotificationStyleType.success,
          duration: Duration(seconds: 4),
        );

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
            _buildCourseHeader(),
            Expanded(
              child: _buildCourseContent(),
            ),
            _buildBottomNavigation(),
          ],
        ),
      ),
    );
  }

  Widget _buildCourseHeader() {
    return Stack(
      children: [
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
              SizedBox(height: 8),
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
              if (!_hasValidSubscription)
                Container(
                  margin: EdgeInsets.only(top: 8, bottom: 8),
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red, width: 1),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: Colors.red, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          trans(
                              "Your subscription has expired. Renew to continue accessing the course."),
                          style: TextStyle(
                              fontSize: 12, color: Colors.red.shade900),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          // Pass curriculum data to avoid API call
                          routeTo(EnrollmentPlanPage.path, data: {
                            'course': _course,
                            'isRenewal': true,
                            'curriculum': _curriculumItems
                          });
                        },
                        child: Text(
                          trans("Renew"),
                          style: TextStyle(fontSize: 12),
                        ),
                        style: TextButton.styleFrom(
                          padding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size(60, 24),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
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

    int nextLessonIndex = _currentLessonIndex;
    for (int i = 0; i < _curriculumItems.length; i++) {
      if (!(_completedLessons[i] ?? false)) {
        nextLessonIndex = i;
        if (i >= _currentLessonIndex) break;
      }
    }

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
