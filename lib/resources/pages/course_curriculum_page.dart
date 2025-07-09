import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/app/services/video_service_utils.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'package:flutter_app/app/models/course.dart';
import 'package:flutter_app/app/services/video_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';

import '../../app/networking/course_api_service.dart';
import '../widgets/courses_tab_widget.dart';
import 'enrollment_plan_page.dart';
import 'package:better_player_plus/better_player_plus.dart';

class CourseCurriculumPage extends NyStatefulWidget {
  static RouteView path = ("/course-curriculum", (_) => CourseCurriculumPage());

  CourseCurriculumPage({super.key})
      : super(child: () => _CourseCurriculumPageState());
}

class _CourseCurriculumPageState extends NyState<CourseCurriculumPage>
    with WidgetsBindingObserver {
  // Data variables
  List<dynamic> curriculumItems = [];
  bool _isOnline = true;
  Course? course;
  String courseName = "";
  String totalVideos = "";
  String totalDuration = "";
  int startIndex = 0;
  BetterPlayerController? _activeVideoController;

  // Download status tracking
  Map<int, bool> _downloadingStatus = {};
  Map<int, bool> _downloadedStatus = {};
  Map<int, double> _downloadProgress = {};
  Map<int, bool> _watermarkingStatus = {};
  Map<int, String> _statusMessages = {};
  Map<int, String> _downloadSpeeds = {};
  Map<int, bool> _queuedStatus = {};
  Map<int, bool> _pausedStatus = {};
  StreamSubscription? _downloadProgressSubscription;
  Map<int, int> _retryCount = {};
  Map<int, DateTime?> _nextRetryTime = {};

  // Progress tracking
  Map<int, bool> _completedLessons = {};

  // Network preferences
  NetworkPreference _currentNetworkPreference = NetworkPreference.any;
  bool _pauseOnMobileData = false;

  // Service
  final VideoService _videoService = VideoService();

  // Stream subscription for progress updates
  StreamSubscription? _progressSubscription;

  // User information
  String _username = "User";
  String _email = "";

  // Scroll controller for the ListView
  final ScrollController _scrollController = ScrollController();

  // Bottom sheet controller
  PersistentBottomSheetController? _bottomSheetController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Listen for download progress updates with robust error handling
    _progressSubscription = _videoService.progressStream.listen(
      (update) {
        try {
          if (!mounted || course == null) return;

          if (update.containsKey('courseId') &&
              update.containsKey('videoId') &&
              update.containsKey('progress')) {
            String courseId = update['courseId'];
            String videoId = update['videoId'];
            double progress = update['progress'];
            bool isWatermarking = update['isWatermarking'] ?? false;
            String statusMessage = update['statusMessage'] ?? "";
            String downloadSpeed = update['downloadSpeed'] ?? "";
            String phase = update['phase'] ?? "";
            int retryCount = update['retryCount'] ?? 0;
            String? nextRetryTimeStr = update['nextRetryTime'];
            DateTime? nextRetryTime;

            if (nextRetryTimeStr != null && nextRetryTimeStr.isNotEmpty) {
              try {
                nextRetryTime = DateTime.parse(nextRetryTimeStr);
              } catch (e) {
                NyLogger.error('Error parsing retry time: $e');
              }
            }

            // Only update if this is for our current course
            if (courseId == course!.id.toString() && mounted) {
              try {
                int index = int.parse(videoId);
                if (index >= 0 && index < curriculumItems.length) {
                  setState(() {
                    _downloadProgress[index] = progress;

                    // Set status based on phase
                    _downloadingStatus[index] =
                        phase == 'DownloadPhase.downloading';
                    _watermarkingStatus[index] =
                        phase == 'DownloadPhase.watermarking';
                    _downloadedStatus[index] =
                        phase == 'DownloadPhase.completed';
                    _queuedStatus[index] = phase == 'DownloadPhase.queued';
                    _pausedStatus[index] = phase == 'DownloadPhase.paused';

                    _statusMessages[index] = statusMessage;
                    _downloadSpeeds[index] = downloadSpeed;
                    _retryCount[index] = retryCount;
                    _nextRetryTime[index] = nextRetryTime;
                  });
                }
              } catch (e) {
                NyLogger.error('Error parsing videoId: $e');
              }
            }
          } else if (update.containsKey('type') &&
              update['type'] == 'error' &&
              mounted) {
            if (update['errorType'] == 'permissionRequired') {
              _handlePermissionRequired();
              return;
            } else if (update['errorType'] == 'permissionPermanentlyDenied') {
              _handlePermissionPermanentlyDenied();
              return;
            } else if (update['errorType'] == 'diskSpace') {
              _showDiskSpaceError(update['message'] ?? "Not enough disk space");
            }
          }
        } catch (e) {
          NyLogger.error('Error processing progress update: $e');
        }
      },
      onError: (error) {
        NyLogger.error('Error in progress stream: $error');
      },
    );

    // Initialize network preferences
    _loadNetworkPreferences();
    // ❌ REMOVED: _setupSubscriptionValidation();
  }

  void _handlePermissionRequired() {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(trans('Permission Required')),
        content:
            Text(trans('Storage permission is needed to download videos.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(trans('Cancel')),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              bool granted =
                  await _videoService.checkAndRequestStoragePermissions();
              if (granted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(trans(
                        'Permission granted! You can now download videos.')),
                    backgroundColor: Colors.green,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        trans('Permission denied. Downloads may not work.')),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: Text(trans('Grant Permission')),
          ),
        ],
      ),
    );
  }

  void _handlePermissionPermanentlyDenied() {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(trans('Permission Required')),
        content: Text(trans(
            'Storage permission has been permanently denied. Please enable it in app settings to download videos.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(trans('Cancel')),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: Text(trans('Open Settings')),
          ),
        ],
      ),
    );
  }

  @override
  get init => () async {
        super.init();
        // Set loading state
        setLoading(true);

        try {
          // Get data passed from previous page
          Map<String, dynamic> pageData = data();

          // Extract course data
          if (pageData.containsKey('course') && pageData['course'] != null) {
            course = pageData['course'];
            courseName = course?.title ?? "Course Curriculum";
            // ❌ REMOVED: _extractSubscriptionDetails();
          } else {
            courseName = "Course Curriculum";
          }

          // Extract curriculum items
          if (pageData.containsKey('curriculum') &&
              pageData['curriculum'] != null) {
            curriculumItems = List<dynamic>.from(pageData['curriculum']);
            totalVideos = "${curriculumItems.length} Videos";
          } else {
            curriculumItems = [];
            totalVideos = "0 Videos";
          }

          // Get start index if provided
          if (pageData.containsKey('startIndex') &&
              pageData['startIndex'] != null) {
            startIndex = pageData['startIndex'];
          }

          // Calculate total duration if available
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
                  // Skip invalid durations
                }
              }
            }
          }

          // Format total duration
          int hours = totalSeconds ~/ 3600;
          int minutes = (totalSeconds % 3600) ~/ 60;
          totalDuration =
              hours > 0 ? "$hours hours $minutes minutes" : "$minutes minutes";

          // Get username for watermarking
          try {
            print("i am here");
            var user = await Auth.data();
            print(user);
            if (user != null) {
              _username = user['full_name'] ?? "User";
              _email = user['email'] ?? "";
            }
          } catch (e) {
            NyLogger.error('Error getting username: $e');
          }

          // Initialize progress tracking
          for (int i = 0; i < curriculumItems.length; i++) {
            _downloadProgress[i] = 0.0;
            _watermarkingStatus[i] = false;
            _statusMessages[i] = "";
            _downloadSpeeds[i] = "";
            _queuedStatus[i] = false;
            _pausedStatus[i] = false;
            _retryCount[i] = 0;
            _nextRetryTime[i] = null;
          }

          // Load lesson completion status
          await _loadLessonCompletionStatus();

          // Check download status for each video
          await _checkDownloadedVideos();

          // Scroll to start index if provided
          _scrollToLesson(startIndex);
          _checkConnectivity();
          Future.delayed(Duration(seconds: 5), () {
            _checkAndCleanupStaleDownloads();
          });
        } catch (e) {
          NyLogger.error('Error initializing curriculum page: $e');
        } finally {
          // Set loading state to false
          setLoading(false);
        }
      };

  Future<bool> _isNetworkSuitable() async {
    try {
      // Check current network status
      var connectivityResult = await Connectivity().checkConnectivity();

      if (connectivityResult.isEmpty ||
          connectivityResult.first == ConnectivityResult.none) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(trans("No internet connection available")),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return false;
      }

      // Check if current network matches preference
      if (_currentNetworkPreference == NetworkPreference.wifiOnly &&
          !connectivityResult.contains(ConnectivityResult.wifi)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(trans("WiFi connection required for downloads")),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return false;
      }

      return true;
    } catch (e) {
      NyLogger.error('Error checking network: $e');
      return true; // Proceed if we can't check
    }
  }

  Future<void> _checkConnectivity() async {
    try {
      var connectivityResult = await Connectivity().checkConnectivity();
      setState(() {
        _isOnline = connectivityResult != ConnectivityResult.none;
      });
    } catch (e) {
      NyLogger.error('Error checking connectivity: $e');
    }
  }

  Future<void> _checkAndCleanupStaleDownloads() async {
    if (course == null) return;

    try {
      // Call the cleanup method in VideoService
      int cleanedCount = await _videoService.cleanupStaleDownloads(
          courseId: course!.id.toString());

      if (cleanedCount > 0) {
        // Refresh the UI
        await _checkDownloadedVideos();

        // Notify user
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(trans("Cleared $cleanedCount stale downloads")),
              backgroundColor: Colors.blue,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      NyLogger.error('Error cleaning up stale downloads: $e');
    }
  }

  void _scrollToLesson(int index) {
    if (index <= 0 || curriculumItems.isEmpty) return;

    // Use a short delay to ensure the list is built
    Future.delayed(Duration(milliseconds: 300), () {
      if (_scrollController.hasClients) {
        // Calculate approximate position - adjust the multiplier based on your item height
        double estimatedItemHeight =
            60.0; // Adjust based on your actual item height
        double offset = index * estimatedItemHeight;

        // Ensure we don't scroll beyond the max extent
        if (offset > _scrollController.position.maxScrollExtent) {
          offset = _scrollController.position.maxScrollExtent;
        }

        _scrollController.animateTo(
          offset,
          duration: Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  Future<void> _loadNetworkPreferences() async {
    try {
      // Load network preferences from VideoService
      _currentNetworkPreference = _videoService.globalNetworkPreference;
      _pauseOnMobileData = _videoService.pauseOnMobileData;
    } catch (e) {
      NyLogger.error('Error loading network preferences: $e');
    }
  }

  void _showDiskSpaceError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(trans(message)),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: trans('Manage Storage'),
          onPressed: () {
            _showStorageManagementOptions();
          },
        ),
      ),
    );
  }

  void _showStorageManagementOptions() {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  trans("Storage Management"),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: Colors.red),
                title: Text(trans("Delete All Downloaded Videos")),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDeleteAllVideos();
                },
              ),
              ListTile(
                leading: Icon(Icons.settings_outlined),
                title: Text(trans("Download Settings")),
                onTap: () {
                  Navigator.pop(context);
                  _showDownloadSettings();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showDownloadSettings() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(trans("Download Settings")),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trans("Network Preference"),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 8),
                    RadioListTile<NetworkPreference>(
                      title: Text(trans("WiFi Only")),
                      value: NetworkPreference.wifiOnly,
                      groupValue: _currentNetworkPreference,
                      onChanged: (NetworkPreference? value) {
                        if (value != null) {
                          setState(() {
                            _currentNetworkPreference = value;
                          });
                        }
                      },
                    ),
                    RadioListTile<NetworkPreference>(
                      title: Text(trans("WiFi & Mobile Data")),
                      value: NetworkPreference.wifiAndMobile,
                      groupValue: _currentNetworkPreference,
                      onChanged: (NetworkPreference? value) {
                        if (value != null) {
                          setState(() {
                            _currentNetworkPreference = value;
                          });
                        }
                      },
                    ),
                    RadioListTile<NetworkPreference>(
                      title: Text(trans("Any Network")),
                      value: NetworkPreference.any,
                      groupValue: _currentNetworkPreference,
                      onChanged: (NetworkPreference? value) {
                        if (value != null) {
                          setState(() {
                            _currentNetworkPreference = value;
                          });
                        }
                      },
                    ),
                    Divider(),
                    SwitchListTile(
                      title: Text(trans("Pause Downloads on Mobile Data")),
                      subtitle: Text(
                        trans(
                            "Automatically pause downloads when switching from WiFi to mobile data"),
                        style: TextStyle(fontSize: 12),
                      ),
                      value: _pauseOnMobileData,
                      onChanged: (bool value) {
                        setState(() {
                          _pauseOnMobileData = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  child: Text(trans("Cancel")),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
                TextButton(
                  child: Text(trans("Save")),
                  onPressed: () {
                    Navigator.of(context).pop();
                    _saveNetworkPreferences();
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _saveNetworkPreferences() async {
    try {
      // Update VideoService settings
      _videoService.globalNetworkPreference = _currentNetworkPreference;
      _videoService.pauseOnMobileData = _pauseOnMobileData;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(trans("Download settings updated")),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      NyLogger.error('Error saving network preferences: $e');
    }
  }

  void _confirmDeleteAllVideos() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(trans("Delete All Downloaded Videos?")),
          content: Text(trans(
              "This will free up storage space but you'll need to download videos again to watch them offline. This action cannot be undone.")),
          actions: [
            TextButton(
              child: Text(trans("Cancel")),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text(trans("Delete All")),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () {
                Navigator.of(context).pop();
                _deleteAllVideos();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteAllVideos() async {
    setLoading(true);

    try {
      int successCount = 0;
      int failedCount = 0;

      // Delete videos in parallel for faster operation
      List<Future<bool>> deleteFutures = [];

      for (int i = 0; i < curriculumItems.length; i++) {
        if (_downloadedStatus[i] == true) {
          final String courseIdStr = course!.id.toString();
          final String videoIdStr = i.toString();

          deleteFutures.add(_videoService
              .deleteVideo(
            courseId: courseIdStr,
            videoId: videoIdStr,
          )
              .then((success) {
            if (success) {
              setState(() {
                _downloadedStatus[i] = false;
                _downloadProgress[i] = 0.0;
                _statusMessages[i] = "";
                _downloadSpeeds[i] = "";
              });
              successCount++;
            } else {
              failedCount++;
            }
            return success;
          }));
        }
      }

      // Wait for all deletions to complete
      await Future.wait(deleteFutures);

      // Update UI based on results
      if (failedCount == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(trans("All $successCount videos deleted successfully")),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                trans("Deleted $successCount videos, $failedCount failed")),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      NyLogger.error('Error deleting all videos: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(trans("Failed to delete all videos: ${e.toString()}")),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      setLoading(false);
    }
  }

  Future<void> _loadLessonCompletionStatus() async {
    if (course == null) return;

    try {
      // Load saved progress from storage
      String key = 'course_progress_${course!.id}';
      dynamic savedProgress = await NyStorage.read(key);

      if (savedProgress == null) return;

      Map<String, dynamic> progressMap = {};

      if (savedProgress is String) {
        try {
          // Try to parse as JSON
          progressMap = jsonDecode(savedProgress);
        } catch (e) {
          NyLogger.error('Error parsing progress string: $e');
          return;
        }
      } else if (savedProgress is Map) {
        // Already a Map, convert to the right type
        progressMap = Map<String, dynamic>.from(savedProgress);
      } else {
        NyLogger.error(
            'Unexpected progress data type: ${savedProgress.runtimeType}');
        return;
      }

      if (progressMap.containsKey('completedLessons')) {
        dynamic savedLessons = progressMap['completedLessons'];

        if (savedLessons is Map) {
          // Convert to our format
          savedLessons.forEach((k, v) {
            // Convert key to int safely
            int? index = int.tryParse(k.toString());
            if (index != null && index >= 0 && index < curriculumItems.length) {
              _completedLessons[index] = v == true;
            }
          });
        }
      }
    } catch (e) {
      NyLogger.error('Error loading lesson completion status: $e');
    }
  }

  // Improved _saveProgress with proper encoding
  Future<void> _saveProgress() async {
    if (course == null) return;

    try {
      // Get existing progress data first
      String key = 'course_progress_${course!.id}';
      dynamic existingData = await NyStorage.read(key);

      Map<String, dynamic> progressData = {};

      // Parse existing data if available
      if (existingData != null) {
        if (existingData is String) {
          try {
            progressData = jsonDecode(existingData);
          } catch (e) {
            NyLogger.error('Error parsing existing progress data: $e');
            // Continue with empty map rather than failing
          }
        } else if (existingData is Map) {
          progressData = Map<String, dynamic>.from(existingData);
        }
      }

      // Convert completed lessons to a map with string keys for JSON serialization
      Map<String, bool> serializedLessons = {};
      _completedLessons.forEach((key, value) {
        serializedLessons[key.toString()] = value;
      });

      // Update the progress data
      progressData['completedLessons'] = serializedLessons;
      progressData['lastUpdated'] = DateTime.now().toIso8601String();

      // Save as JSON string to ensure consistent format
      String jsonData = jsonEncode(progressData);
      await NyStorage.save(key, jsonData);

      // Notify CourseTab about progress change
      updateState(CoursesTab, data: "update_course_progress");
    } catch (e) {
      NyLogger.error('Error saving progress: $e');
    }
  }

  Future<VideoPlayerController> _createOptimizedController({
    required String videoPath,
    required bool isLocal,
    String quality = '240p',
  }) async {
    VideoPlayerController controller;

    if (isLocal) {
      controller = VideoPlayerController.file(File(videoPath));
    } else {
      // Default to 240p for network videos
      String optimizedUrl = _getQualityUrl(videoPath, quality);

      controller = VideoPlayerController.networkUrl(
        Uri.parse(optimizedUrl),
        httpHeaders: {
          'User-Agent':
              'Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15',
          'Accept': '*/*',
          'Connection': 'keep-alive',
          'Cache-Control': 'no-cache', // Reduce buffering issues
        },
        formatHint: VideoFormat.hls, // Explicitly set HLS format
      );
    }

    await controller.initialize();

    // Set initial quality to 240p for data saving
    if (!isLocal) {
      controller.setPlaybackSpeed(1.0);
    }

    return controller;
  }

  String _getQualityUrl(String baseUrl, String quality) {
    // Modify based on your streaming setup
    if (baseUrl.contains('.m3u8')) {
      // HLS stream - append quality parameter
      return baseUrl.replaceAll('master.m3u8', '${quality}.m3u8');
    } else {
      // Regular MP4 - add quality parameter
      return '$baseUrl?quality=$quality';
    }
  }

  @override
  void dispose() {
    // Cancel stream subscription to avoid memory leaks
    _progressSubscription?.cancel();
    _scrollController.dispose();
    _activeVideoController?.dispose(); // Simplified disposal
    _activeVideoController = null;
    // Close bottom sheet if open
    _bottomSheetController?.close();
    _downloadProgressSubscription?.cancel();
    _progressSubscription = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // Pause/stop video when app goes to background
      _activeVideoController?.pause();
    }
  }

  Future<void> _checkDownloadedVideos() async {
    if (course == null) return;

    const int batchSize = 5; // Process videos in small batches
    final int totalItems = curriculumItems.length;

    for (int startIdx = 0; startIdx < totalItems; startIdx += batchSize) {
      // Process a batch of videos
      final int endIdx = min(startIdx + batchSize, totalItems);

      for (var i = startIdx; i < endIdx; i++) {
        var item = curriculumItems[i];
        if (item.containsKey('video_url') && item['video_url'] != null) {
          final String courseIdStr = course!.id.toString();
          final String videoIdStr = i.toString();

          // Check if already downloaded
          bool isDownloaded = await _videoService.isVideoDownloaded(
            videoUrl: item['video_url'],
            courseId: courseIdStr,
            videoId: videoIdStr,
          );

          // Check if currently downloading
          bool isDownloading =
              _videoService.isDownloading(courseIdStr, videoIdStr);

          // Check if watermarking
          bool isWatermarking =
              _videoService.isWatermarking(courseIdStr, videoIdStr);

          // Check if queued
          bool isQueued = _videoService.isQueued(courseIdStr, videoIdStr);

          // Get current progress
          double progress = 0.0;
          if (isDownloading || isWatermarking) {
            progress = _videoService.getProgress(courseIdStr, videoIdStr);
          } else if (isDownloaded) {
            progress = 1.0;
          }

          // Get detailed status
          VideoDownloadStatus status =
              _videoService.getDetailedStatus(courseIdStr, videoIdStr);
          String statusMessage = status.displayMessage;

          if (mounted) {
            setState(() {
              _downloadedStatus[i] = isDownloaded &&
                  !isDownloading &&
                  !isWatermarking &&
                  !isQueued;
              _downloadingStatus[i] = isDownloading;
              _watermarkingStatus[i] = isWatermarking;
              _downloadProgress[i] = progress;
              _statusMessages[i] = statusMessage;
              _queuedStatus[i] = isQueued;
              _pausedStatus[i] = status.isPaused;

              if (isDownloading) {
                _downloadSpeeds[i] =
                    _videoService.getDownloadSpeed(courseIdStr, videoIdStr);
              } else {
                _downloadSpeeds[i] = "";
              }
            });
          }
        }
      }

      // Yield to the UI thread between batches to prevent jank
      if (endIdx < totalItems) {
        await Future.delayed(Duration(milliseconds: 10));
      }
    }
  }

  Future<void> _cancelDownload(int index) async {
    if (course == null) return;
    final String courseIdStr = course!.id.toString();
    final String videoIdStr = index.toString();

    bool success = await _videoService.cancelDownload(
      courseId: courseIdStr,
      videoId: videoIdStr,
    );

    if (success) {
      setState(() {
        _downloadingStatus[index] = false;
        _watermarkingStatus[index] = false;
        _downloadProgress[index] = 0.0;
        _statusMessages[index] = "Download cancelled";
        _downloadSpeeds[index] = "";
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(trans("Download canceled")),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(trans("Failed to cancel download")),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // ✅ SIMPLIFIED: Removed subscription validation
  Future<void> _downloadVideo(int index, {bool isRedownload = false}) async {
    if (course == null) return;

    // ❌ REMOVED: Subscription validation
    // if (!await _validateSubscriptionForDownload()) {
    //   return;
    // }

    try {
      // Check permissions
      bool hasPermission =
          await _videoService.checkAndRequestStoragePermissions();
      if (!hasPermission) {
        return;
      }

      setState(() {
        _statusMessages[index] = "";
      });

      // Get string identifiers
      final String courseIdStr = course!.id.toString();
      final String videoIdStr = index.toString();

      // Reset status in VideoService to ensure clean state
      if (isRedownload) {
        await _videoService.deleteVideo(
          courseId: courseIdStr,
          videoId: videoIdStr,
        );

        setState(() {
          _downloadedStatus[index] = false;
          _downloadProgress[index] = 0.0;
        });
      } else {
        // Check current status from service
        bool isCurrentlyDownloading =
            _videoService.isDownloading(courseIdStr, videoIdStr);
        bool isCurrentlyWatermarking =
            _videoService.isWatermarking(courseIdStr, videoIdStr);
        bool isCurrentlyQueued =
            _videoService.isQueued(courseIdStr, videoIdStr);

        // If download already in progress or queued, show message and return
        if (isCurrentlyDownloading ||
            isCurrentlyWatermarking ||
            isCurrentlyQueued) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(trans("Download already in progress")),
              backgroundColor: Colors.amber,
              duration: const Duration(seconds: 2),
            ),
          );
          return;
        }

        // If there was a previous error, cancel the download first to reset state
        await _videoService.cancelDownload(
          courseId: courseIdStr,
          videoId: videoIdStr,
        );
      }

      var item = curriculumItems[index];
      if (!item.containsKey('video_url') ||
          item['video_url'] == null ||
          item['video_url'].toString().trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(trans("Video URL not available")),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }

      // Verify network connectivity before starting download
      bool hasConnection = await _checkNetworkConnectivity();
      if (!hasConnection) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(trans(
                "No internet connection. Please check your network and try again.")),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }

      // Log the video URL to help with debugging
      NyLogger.info('Starting download for video URL: ${item['video_url']}');

      // Update UI immediately to show queued status
      setState(() {
        _downloadingStatus[index] = false;
        _watermarkingStatus[index] = false;
        _queuedStatus[index] = true;
        _downloadedStatus[index] = false;
        _statusMessages[index] = "Preparing to download...";
      });

      // Get username for watermarking
      String username = _username;
      String email = _email;

      // Launch the download in a microtask to avoid blocking UI
      Future.microtask(() async {
        try {
          // Use a timeout to prevent indefinite waiting
          bool enqueued = await _videoService
              .enqueueDownload(
            videoUrl: item['video_url'],
            courseId: courseIdStr,
            videoId: videoIdStr,
            watermarkText: username,
            email: email,
            course: course!,
            curriculum: curriculumItems,
            networkPreference: _currentNetworkPreference,
          )
              .timeout(Duration(seconds: 30), onTimeout: () {
            NyLogger.error('Timeout enqueueing download');
            return false;
          });

          if (mounted) {
            if (!enqueued) {
              setState(() {
                _queuedStatus[index] = false;
                _statusMessages[index] = "Failed to start download";
              });

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      trans("Failed to start download. Please try again.")),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 3),
                ),
              );
            } else {
              // Successfully queued
              NyLogger.info(
                  'Successfully queued download for video $videoIdStr in course $courseIdStr');
            }
          }
        } catch (e) {
          NyLogger.error('Error enqueueing download: $e');
          if (mounted) {
            setState(() {
              _queuedStatus[index] = false;
              _statusMessages[index] =
                  "Error: ${e.toString().substring(0, min(e.toString().length, 50))}";
            });

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(trans("Download error: Please try again")),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      });
    } catch (e) {
      NyLogger.error('Error in _downloadVideo: $e');
      if (mounted) {
        setState(() {
          _downloadingStatus[index] = false;
          _watermarkingStatus[index] = false;
          _queuedStatus[index] = false;
          _statusMessages[index] =
              "Download failed: ${e.toString().substring(0, min(e.toString().length, 50))}";
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(trans("Download failed. Please try again.")),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<bool> _checkNetworkConnectivity() async {
    try {
      var connectivityResult = await Connectivity().checkConnectivity();
      return connectivityResult.isNotEmpty &&
          connectivityResult.first != ConnectivityResult.none;
    } catch (e) {
      NyLogger.error('Error checking connectivity: $e');
      return true; // Assume connection exists if we can't check
    }
  }

  Future<void> _showPlaybackOptionsDialog(int index, String videoTitle) async {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.all(16),
                child: Text("Choose Playback Option",
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              ListTile(
                leading: Icon(Icons.download_done, color: Colors.green),
                title: Text(trans("Play Downloaded Video")),
                subtitle: Text(trans("Offline • No data usage")),
                onTap: () {
                  Navigator.pop(context);
                  _launchVideoPlayer(
                      index: index,
                      preferOffline: true,
                      videoTitle: videoTitle);
                },
              ),
              ListTile(
                leading: Icon(Icons.cloud, color: Colors.blue),
                title: Text(trans("Stream Online")),
                subtitle: Text(trans("Latest version • Uses data")),
                onTap: () {
                  Navigator.pop(context);
                  _launchVideoPlayer(
                      index: index,
                      preferOffline: false,
                      videoTitle: videoTitle);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showStreamOrDownloadOptions(int index) {
    var item = curriculumItems[index];
    String videoTitle = item['title'] ?? 'Video ${index + 1}';

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.all(16),
                child: Text(videoTitle,
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              ListTile(
                leading: Icon(Icons.play_circle_filled, color: Colors.blue),
                title: Text(trans("Stream Now")),
                subtitle: Text(trans("Watch immediately • Uses data")),
                onTap: () {
                  Navigator.pop(context);
                  _launchVideoPlayer(
                      index: index,
                      preferOffline: false,
                      videoTitle: videoTitle);
                },
              ),
              ListTile(
                leading: Icon(Icons.download_for_offline, color: Colors.green),
                title: Text(trans("Download First")),
                subtitle: Text(trans("Save for offline viewing")),
                onTap: () {
                  Navigator.pop(context);
                  _downloadVideo(index);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _launchVideoPlayer({
    required int index,
    required bool preferOffline,
    required String videoTitle,
  }) async {
    try {
      var item = curriculumItems[index];
      String? videoUrl = item['video_url'];
      String? localVideoPath;

      if (preferOffline) {
        localVideoPath = await _videoService.getVideoFilePath(
            course!.id.toString(), index.toString());

        await _showBetterVideoPlayer(
            videoPath: localVideoPath, videoTitle: videoTitle, isLocal: true);
      } else {
        if (videoUrl != null && videoUrl.isNotEmpty) {
          await _showBetterVideoPlayer(
              videoPath: videoUrl, videoTitle: videoTitle, isLocal: false);
        }
      }

      // Mark as completed
      setState(() {
        _completedLessons[index] = true;
      });
      await _saveProgress();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(trans("Failed to play video"))),
      );
    }
  }

  Future<void> _showBetterVideoPlayer({
    required String videoPath,
    required String videoTitle,
    required bool isLocal,
  }) async {
    try {
      // Dispose any existing controller first
      _activeVideoController?.dispose();
      // Create the configuration for optimal playback
      BetterPlayerConfiguration betterPlayerConfiguration =
          BetterPlayerConfiguration(
        aspectRatio: 16 / 9,
        autoPlay: true,
        looping: false,
        fullScreenByDefault: true,
        allowedScreenSleep: false,

        autoDetectFullscreenDeviceOrientation: true,
        autoDetectFullscreenAspectRatio: true,
        deviceOrientationsOnFullScreen: [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
        systemOverlaysAfterFullScreen: SystemUiOverlay.values,
        deviceOrientationsAfterFullScreen: [DeviceOrientation.portraitUp],
        controlsConfiguration: BetterPlayerControlsConfiguration(
          enablePlayPause: true,
          enableMute: true,
          enableFullscreen: true,
          enableSkips: true,
          enableProgressText: true,
          enableProgressBar: true,
          enablePlaybackSpeed: true,
          enablePip: false,
          enableRetry: true,
          showControlsOnInitialize: true,
          controlsHideTime: Duration(seconds: 3),
          progressBarPlayedColor: Colors.amber,
          progressBarHandleColor: Colors.amber,
          progressBarBackgroundColor: Colors.white.withOpacity(0.3),
          loadingColor: Colors.amber,
          iconsColor: Colors.white,
          overflowModalColor: Colors.black87,
          overflowModalTextColor: Colors.white,
          overflowMenuIconsColor: Colors.white,
          playIcon: Icons.play_arrow,
          pauseIcon: Icons.pause,
          muteIcon: Icons.volume_off,
          unMuteIcon: Icons.volume_up,
          fullscreenEnableIcon: Icons.fullscreen,
          fullscreenDisableIcon: Icons.fullscreen_exit,
          backwardSkipTimeInMilliseconds: 10000,
          forwardSkipTimeInMilliseconds: 10000,
        ),
        // Enhanced buffering for smooth playback

        // Error handling
        errorBuilder: (context, errorMessage) {
          return Container(
            color: Colors.black,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, color: Colors.red, size: 64),
                  SizedBox(height: 16),
                  Text(
                    trans("Video Error"),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    errorMessage ?? trans("Unknown error occurred"),
                    style: TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.amber),
                    child: Text(trans("Close")),
                  ),
                ],
              ),
            ),
          );
        },
      );

      // Create data source based on local or network
      BetterPlayerDataSource dataSource;

      if (isLocal) {
        dataSource = BetterPlayerDataSource(
          BetterPlayerDataSourceType.file,
          bufferingConfiguration: BetterPlayerBufferingConfiguration(
            minBufferMs: 5000, // 5 seconds min buffer
            maxBufferMs: 30000, // 30 seconds max buffer
            bufferForPlaybackMs: 2500, // 2.5 seconds to start playback
            bufferForPlaybackAfterRebufferMs: 5000, // 5 seconds after rebuffer
          ),
          videoPath,
          placeholder: Container(
            color: Colors.black,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.amber),
                  SizedBox(height: 16),
                  Text(
                    trans("Loading downloaded video..."),
                    style: TextStyle(color: Colors.white),
                  ),
                  SizedBox(height: 8),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.download_done,
                            color: Colors.white, size: 16),
                        SizedBox(width: 4),
                        Text(
                          trans("Offline"),
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      } else {
        dataSource = BetterPlayerDataSource(
            BetterPlayerDataSourceType.network, videoPath,
            bufferingConfiguration: BetterPlayerBufferingConfiguration(
              minBufferMs: 3000, // 3 seconds min
              maxBufferMs: 15000, // 15 seconds max
              bufferForPlaybackMs: 1500, // 1.5 seconds to start ⭐
              bufferForPlaybackAfterRebufferMs:
                  3000, // 3 seconds after rebuffer
            ),
            // Optimized caching for network videos
            cacheConfiguration: BetterPlayerCacheConfiguration(
              useCache: true,
              preCacheSize: 1 * 1024 * 1024, // 20MB pre-cache
              maxCacheSize: 200 * 1024 * 1024 * 1024, // 200MB max cache
              maxCacheFileSize: 100 * 1024 * 1024 * 1024, // 100MB max file
              key: "cache_${videoPath.hashCode}",
            ),
            // Enhanced headers for better compatibility
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15',
              'Accept': '*/*',
              'Accept-Encoding': 'identity',
              'Range': 'bytes=0-',
              'Connection': 'keep-alive',
            },
            //   // Loading placeholder
            placeholder: Container());

        _activeVideoController = BetterPlayerController(
          betterPlayerConfiguration,
          betterPlayerDataSource: dataSource,
        );
      }

      // Show the video player in fullscreen dialog
      await showDialog(
        context: context,
        barrierDismissible: false,
        useSafeArea: false,
        builder: (BuildContext context) {
          return WillPopScope(
            onWillPop: () async {
              _activeVideoController?.dispose();
              _activeVideoController = null;
              return true;
            },
            child: Scaffold(
              backgroundColor: Colors.black,
              body: Stack(
                children: [
                  // Video player
                  Center(
                    child: BetterPlayer(
                      controller: _activeVideoController!,
                    ),
                  ),

                  // Custom header overlay - KEEP ALL YOUR EXISTING UI
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.8),
                            Colors.black.withOpacity(0.4),
                            Colors.transparent,
                          ],
                          stops: [0.0, 0.5, 1.0],
                        ),
                      ),
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            children: [
                              // Close button
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.5),
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  icon: Icon(Icons.close,
                                      color: Colors.white, size: 24),
                                  padding: EdgeInsets.all(8),
                                ),
                              ),

                              SizedBox(width: 12),

                              // Video title
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      videoTitle,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      isLocal
                                          ? trans("Downloaded Video")
                                          : trans("Streaming Video"),
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              SizedBox(width: 12),

                              // Status indicator
                              Container(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isLocal
                                      ? Colors.green.withOpacity(0.9)
                                      : Colors.blue.withOpacity(0.9),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.3),
                                      blurRadius: 4,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isLocal
                                          ? Icons.download_done
                                          : Icons.cloud,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      isLocal
                                          ? trans("Offline")
                                          : trans("Streaming"),
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ).then((_) {
        // Dispose controller when dialog closes
        _activeVideoController?.dispose();
        _activeVideoController = null;
      }).catchError((error) {
        // ✅ ADD ERROR HANDLING
        _activeVideoController?.dispose();
        _activeVideoController = null;
      });
    } catch (e) {
      // ✅ ENSURE CLEANUP ON ERRORS
      _activeVideoController?.dispose();
      _activeVideoController = null;
      // ... your error handling
    }
  }

  void _handleVideoTap(int index) {
    bool isDownloaded = _downloadedStatus[index] ?? false;
    bool isDownloading = _downloadingStatus[index] ?? false;
    bool isWatermarking = _watermarkingStatus[index] ?? false;
    bool isQueued =
        _videoService.isQueued(course!.id.toString(), index.toString());

    var item = curriculumItems[index];
    bool hasOnlineUrl =
        item['video_url'] != null && item['video_url'].toString().isNotEmpty;

    if (isDownloading || isWatermarking) {
      _showProcessingOptions(index);
    } else if (isQueued) {
      _showQueuedOptions(index);
    } else if (isDownloaded) {
      _showDownloadedOptions(index);
    } else if (hasOnlineUrl && _isOnline) {
      _showStreamOrDownloadOptions(index);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(trans("Video unavailable"))),
      );
    }
  }

  Future<void> _playVideo(int index) async {
    if (course == null) return;

    var item = curriculumItems[index];
    bool isDownloaded = _downloadedStatus[index] ?? false;
    String? videoUrl = item['video_url'];
    String videoTitle = item['title'] ?? 'Video ${index + 1}';

    // Check network connectivity
    bool hasNetwork = await _checkNetworkConnectivity();

    // Determine available playback options
    bool canStreamOnline =
        hasNetwork && videoUrl != null && videoUrl.isNotEmpty;
    bool canPlayOffline = isDownloaded;

    if (!canStreamOnline && !canPlayOffline) {
      // Show error and offer download
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(trans("No internet connection and video not downloaded")),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // If both options available, show choice dialog
    if (canStreamOnline && canPlayOffline) {
      await _showPlaybackOptionsDialog(index, videoTitle);
    } else if (canPlayOffline) {
      await _launchVideoPlayer(
          index: index, preferOffline: true, videoTitle: videoTitle);
    } else {
      await _launchVideoPlayer(
          index: index, preferOffline: false, videoTitle: videoTitle);
    }
  }

  // ✅ SIMPLIFIED: Removed subscription validation from video tap handler

  void _showDownloadedOptions(int index) {
    bool isCompleted = _completedLessons[index] ?? false;
    var item = curriculumItems[index]; // Add this line
    bool hasOnlineUrl = item['video_url'] != null &&
        item['video_url'].toString().isNotEmpty; // Add this line

    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Play offline option
                ListTile(
                  leading: Container(
                    padding: EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.download_done,
                        color: Colors.green, size: 20),
                  ),
                  title: Text(trans("Play Downloaded Video")),
                  subtitle: Text(trans("Offline • Best quality")),
                  onTap: () {
                    Navigator.pop(context);
                    _launchVideoPlayer(
                      index: index,
                      preferOffline: true,
                      videoTitle: item['title'] ?? 'Video ${index + 1}',
                    );
                  },
                ),

                // Play online option (if available)
                if (hasOnlineUrl && _isOnline)
                  ListTile(
                    leading: Container(
                      padding: EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(Icons.cloud, color: Colors.blue, size: 20),
                    ),
                    title: Text(trans("Stream Online")),
                    subtitle: Text(trans("Uses data • Latest version")),
                    onTap: () {
                      Navigator.pop(context);
                      _launchVideoPlayer(
                        index: index,
                        preferOffline: false,
                        videoTitle: item['title'] ?? 'Video ${index + 1}',
                      );
                    },
                  ),

                Divider(),

                if (!isCompleted)
                  ListTile(
                    leading:
                        Icon(Icons.check_circle_outline, color: Colors.green),
                    title: Text(trans("Mark as completed")),
                    onTap: () {
                      Navigator.pop(context);
                      _markAsCompleted(index);
                    },
                  )
                else
                  ListTile(
                    leading:
                        Icon(Icons.remove_circle_outline, color: Colors.orange),
                    title: Text(trans("Mark as not completed")),
                    onTap: () {
                      Navigator.pop(context);
                      _markAsNotCompleted(index);
                    },
                  ),
                ListTile(
                  leading: Icon(Icons.refresh, color: Colors.orange),
                  title: Text(trans("Redownload video")),
                  onTap: () {
                    Navigator.pop(context);
                    _showRedownloadConfirmation(index);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.delete_outline, color: Colors.red),
                  title: Text(trans("Delete video")),
                  onTap: () {
                    Navigator.pop(context);
                    _showDeleteConfirmation(index);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Show options for queued videos
  void _showQueuedOptions(int index) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Text(
                        trans("Queued for download"),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        trans(
                            "This video is in the download queue and will be downloaded shortly."),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: Colors.grey[300]),
                ListTile(
                  leading: Icon(Icons.cancel_outlined, color: Colors.red),
                  title: Text(trans("Cancel download")),
                  onTap: () {
                    Navigator.pop(context);
                    _cancelDownload(index);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.priority_high, color: Colors.blue),
                  title: Text(trans("Prioritize download")),
                  onTap: () {
                    Navigator.pop(context);
                    _prioritizeDownload(index);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _prioritizeDownload(int index) async {
    if (course == null) return;
    final String courseIdStr = course!.id.toString();
    final String videoIdStr = index.toString();

    try {
      // Call the new method in VideoService
      bool success = await _videoService.prioritizeDownload(
        courseId: courseIdStr,
        videoId: videoIdStr,
      );

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(trans("Download prioritized")),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(trans("Failed to prioritize download")),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      NyLogger.error('Error prioritizing download: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(trans("Error prioritizing download")),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // Mark lesson as completed manually
  Future<void> _markAsCompleted(int index) async {
    setState(() {
      _completedLessons[index] = true;
    });

    await _saveProgress();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(trans("Lesson marked as completed")),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // Mark lesson as not completed
  Future<void> _markAsNotCompleted(int index) async {
    setState(() {
      _completedLessons[index] = false;
    });

    await _saveProgress();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(trans("Lesson marked as not completed")),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // Show options for downloading/watermarking videos
  void _showProcessingOptions(int index) {
    bool isWatermarking = _watermarkingStatus[index] ?? false;
    double progress = _downloadProgress[index] ?? 0.0;
    String statusMessage = _statusMessages[index] ?? "";
    String downloadSpeed = _downloadSpeeds[index] ?? "";
    String courseIdStr = course!.id.toString();
    String videoIdStr = index.toString();
    String timeRemaining =
        _videoService.getEstimatedTimeRemaining(courseIdStr, videoIdStr);

    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 8.0),
                  child: Column(
                    children: [
                      // Phase indicator
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            isWatermarking
                                ? trans("Watermarking Phase")
                                : trans("Download Phase"),
                            style: TextStyle(
                              color:
                                  isWatermarking ? Colors.orange : Colors.amber,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            "${(progress * 100).toInt()}%",
                            style: TextStyle(
                              color:
                                  isWatermarking ? Colors.orange : Colors.amber,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      // Progress bar with distinct colors
                      LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.grey[300],
                        valueColor: AlwaysStoppedAnimation<Color>(
                            isWatermarking ? Colors.orange : Colors.amber),
                      ),
                      SizedBox(height: 8),
                      // Descriptive message about current process
                      Text(
                        statusMessage.isNotEmpty
                            ? statusMessage
                            : (isWatermarking
                                ? trans(
                                    "Adding watermark with your name and email...")
                                : trans("Downloading video from server...")),
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontSize: 12,
                        ),
                      ),
                      // Download speed (only shown during download phase)
                      if (!isWatermarking && downloadSpeed.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            downloadSpeed,
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      if (timeRemaining.isNotEmpty)
                        // Add this to your UI
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            trans("Estimated time remaining: $timeRemaining"),
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 12,
                            ),
                          ),
                        )
                    ],
                  ),
                ),
                SizedBox(height: 8),
                Divider(height: 1, color: Colors.grey[300]),
                SizedBox(height: 8),
                // Cancel button
                ListTile(
                  leading: Icon(Icons.cancel_outlined, color: Colors.red),
                  title: Text(trans("Cancel download")),
                  onTap: () {
                    Navigator.pop(context);
                    _cancelDownload(index);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Confirm redownload dialog
  void _showRedownloadConfirmation(int index) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(trans("Redownload video")),
          content: Text(trans(
              "Do you want to delete the current file and download again? The video will be re-watermarked with your name and email.")),
          actions: [
            TextButton(
              child: Text(trans("Cancel")),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text(trans("Redownload")),
              style: TextButton.styleFrom(foregroundColor: Colors.orange),
              onPressed: () {
                Navigator.of(context).pop();
                _downloadVideo(index, isRedownload: true);
              },
            ),
          ],
        );
      },
    );
  }

  // Confirm delete dialog
  void _showDeleteConfirmation(int index) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(trans("Delete video")),
          content: Text(trans(
              "Are you sure you want to delete this video? You can download it again later.")),
          actions: [
            TextButton(
              child: Text(trans("Cancel")),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text(trans("Delete")),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () {
                Navigator.of(context).pop();
                _deleteVideo(index);
              },
            ),
          ],
        );
      },
    );
  }

  // Delete a video
  Future<void> _deleteVideo(int index) async {
    if (course == null) return;
    final String courseIdStr = course!.id.toString();
    final String videoIdStr = index.toString();

    bool success = await _videoService.deleteVideo(
      courseId: courseIdStr,
      videoId: videoIdStr,
    );

    if (success) {
      setState(() {
        _downloadedStatus[index] = false;
        _downloadProgress[index] = 0.0;
        _statusMessages[index] = "";
        _downloadSpeeds[index] = "";
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(trans("Video deleted")),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(trans("Failed to delete video")),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // Download all videos for offline viewing
  Future<void> _downloadAllVideos() async {
    if (course == null || curriculumItems.isEmpty) return;

    // Confirm with user
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
          username = user['full_name'] ?? "User";
          email = user['email'] ?? "";
        }
      } catch (e) {
        NyLogger.error('Error getting username: $e');
      }

      // Use the new batch download method in VideoService
      bool success = await _videoService.downloadAllVideos(
        courseId: course!.id.toString(),
        course: course!,
        curriculum: curriculumItems,
        watermarkText: username,
        email: email,
      );

      if (success) {
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(trans(
                "Videos are queued for download. You can continue using the app while downloads complete in the background.")),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );

        // Wait a moment then refresh status
        Future.delayed(Duration(seconds: 1), () {
          _checkDownloadedVideos();
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(trans("No new videos to download")),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(trans("Failed to queue downloads: $e")),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
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
        leading: Padding(
          padding: const EdgeInsets.only(left: 10.0),
          child: IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => pop(),
            padding: EdgeInsets.zero,
          ),
        ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Course Curriculum",
              style: TextStyle(
                color: Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 2),
            Text(
              "$totalVideos | $totalDuration total length",
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[700],
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        centerTitle: false,
        actions: [
          // Network indicator
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: _buildNetworkIndicator(),
          ),
          // Download all button
          IconButton(
            icon: Icon(Icons.download, color: Colors.black),
            onPressed: _downloadAllVideos,
            tooltip: trans("Download All"),
          ),
        ],
      ),
      body: Column(
        children: [
          // ❌ REMOVED: Expired subscription banner
          // if (_showExpiredBanner) _buildExpiredSubscriptionBanner(),
          if (!_isOnline)
            Container(
              width: double.infinity,
              color: Colors.grey[800],
              padding:
                  const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
              child: Row(
                children: [
                  Icon(Icons.cloud_off, color: Colors.white, size: 16),
                  SizedBox(width: 8),
                  Text(
                    trans("You're offline. Some features may be limited."),
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
          Expanded(
            child: afterLoad(
              child: () => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Divider
                  Divider(height: 1, thickness: 1, color: Colors.grey[200]),

                  // Content - using Expanded with SingleChildScrollView for scrollable content
                  Expanded(
                    child: curriculumItems.isEmpty
                        ? _buildEmptyState()
                        : SingleChildScrollView(
                            controller: _scrollController,
                            physics: AlwaysScrollableScrollPhysics(),
                            child: Column(
                              children: [
                                ListView.separated(
                                  shrinkWrap: true,
                                  physics: NeverScrollableScrollPhysics(),
                                  padding: EdgeInsets.zero,
                                  itemCount: curriculumItems.length,
                                  separatorBuilder: (context, index) => Divider(
                                    height: 1,
                                    thickness: 1,
                                    color: Colors.grey[200],
                                  ),
                                  itemBuilder: (context, index) {
                                    final item = curriculumItems[index];
                                    final bool isDownloaded =
                                        _downloadedStatus[index] ?? false;
                                    final bool isDownloading =
                                        _downloadingStatus[index] ?? false;
                                    final bool isWatermarking =
                                        _watermarkingStatus[index] ?? false;
                                    final double progress =
                                        _downloadProgress[index] ?? 0.0;
                                    final String statusMessage =
                                        _statusMessages[index] ?? "";
                                    final bool isCompleted =
                                        _completedLessons[index] ?? false;

                                    return _buildLessonItem(
                                      (index + 1).toString(),
                                      item['title'] ?? 'Video',
                                      item['duration'] ?? '-:--',
                                      isDownloaded: isDownloaded,
                                      isDownloading: isDownloading,
                                      isWatermarking: isWatermarking,
                                      isCompleted: isCompleted,
                                      progress: progress,
                                      statusMessage: statusMessage,
                                      onTap: () => _handleVideoTap(index),
                                    );
                                  },
                                ),
                                // Extra space at bottom for comfort
                                SizedBox(height: 24),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Add this to your widget build method, perhaps in the AppBar actions
  Widget _buildNetworkIndicator() {
    IconData iconData;
    Color iconColor;
    String tooltipMessage;

    if (_currentNetworkPreference == NetworkPreference.wifiOnly) {
      iconData = Icons.wifi;
      iconColor = Colors.green;
      tooltipMessage = trans("WiFi Only");
    } else if (_currentNetworkPreference == NetworkPreference.wifiAndMobile) {
      iconData = Icons.network_cell;
      iconColor = Colors.amber;
      tooltipMessage = trans("WiFi & Mobile Data");
    } else {
      iconData = Icons.public;
      iconColor = Colors.blue;
      tooltipMessage = trans("Any Network");
    }

    return Tooltip(
      message: tooltipMessage,
      child: Icon(iconData, color: iconColor, size: 20),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.video_library_outlined,
            size: 64,
            color: Colors.grey[400],
          ),
          SizedBox(height: 16),
          Text(
            trans("No curriculum items available"),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
          SizedBox(height: 8),
          Text(
            trans("Check back later for updates"),
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLessonItem(
    String number,
    String title,
    String duration, {
    required bool isDownloaded,
    required bool isDownloading,
    required bool isWatermarking,
    required bool isCompleted,
    required double progress,
    String statusMessage = "",
    required VoidCallback onTap,
  }) {
    // Check if queued
    bool isQueued = false;
    if (course != null) {
      int index = int.tryParse(number) ?? -1;
      isQueued =
          _videoService.isQueued(course!.id.toString(), index.toString());
    }

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Lesson number
            Container(
              width: 24,
              child: Text(
                number,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: isCompleted
                      ? Colors.amber
                      : (isDownloaded ? Colors.grey.shade700 : Colors.black),
                ),
              ),
            ),
            SizedBox(width: 12),

            // Lesson details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                      color: isCompleted
                          ? Colors.amber
                          : (isDownloaded
                              ? Colors.grey.shade700
                              : Colors.black),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Video · $duration',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 8,
                    ),
                  ),
                  // Show progress bar if downloading or watermarking
                  if (isDownloading || isWatermarking)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: EdgeInsets.only(top: 4),
                          height: 3,
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: Colors.grey[300],
                            valueColor: AlwaysStoppedAnimation<Color>(
                                isWatermarking ? Colors.orange : Colors.amber),
                          ),
                        ),
                        if (statusMessage.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2.0),
                            child: Text(
                              statusMessage,
                              style: TextStyle(
                                fontSize: 6,
                                color: Colors.grey[600],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  // Show queued indicator
                  if (isQueued)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            margin: EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                              color: Colors.amber,
                              shape: BoxShape.circle,
                            ),
                          ),
                          Text(
                            trans("Queued for download"),
                            style: TextStyle(
                              fontSize: 6,
                              color: Colors.amber,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // Status indicators
            (isDownloading || isWatermarking)
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "${(progress * 100).toInt()}%",
                        style: TextStyle(
                          fontSize: 10,
                          color: isWatermarking ? Colors.orange : Colors.amber,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 4),
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          value: progress,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              isWatermarking ? Colors.orange : Colors.amber),
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(
                        Icons.more_vert,
                        color: Colors.grey[500],
                        size: 20,
                      ),
                    ],
                  )
                : isQueued
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.hourglass_bottom,
                            color: Colors.amber.withOpacity(0.7),
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Icon(
                            Icons.more_vert,
                            color: Colors.grey[500],
                            size: 20,
                          ),
                        ],
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Completion indicator
                          if (isCompleted)
                            Icon(
                              Icons.check_circle,
                              color: Colors.amber,
                              size: 20,
                            )
                          else
                            Icon(
                              isDownloaded
                                  ? Icons.play_circle_outline
                                  : Icons.download_outlined,
                              color: isDownloaded
                                  ? Colors.amber
                                  : Colors.grey[400],
                              size: 24,
                            ),

                          // Menu indicator for downloaded videos
                          if (isDownloaded)
                            Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: Icon(
                                Icons.more_vert,
                                color: Colors.grey[500],
                                size: 20,
                              ),
                            ),
                        ],
                      ),
          ],
        ),
      ),
    );
  }
}
