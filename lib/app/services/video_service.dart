import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/app/models/course.dart';
import 'package:flutter_app/app/services/video_download_manager.dart';
import 'package:flutter_app/app/services/video_storage_manager.dart';
import 'package:flutter_app/app/services/video_watermark_manager.dart';
import 'package:flutter_app/app/services/video_service_utils.dart';
import 'package:flutter_app/resources/pages/enrollment_plan_page.dart';
import 'package:flutter_app/resources/pages/video_player_page.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'package:permission_handler/permission_handler.dart';

class VideoService {
  // Singleton instance
  static final VideoService _instance = VideoService._internal();
  factory VideoService() => _instance;
  VideoService._internal();

  // Core managers
  late final VideoDownloadManager _downloadManager;
  late final VideoStorageManager _storageManager;
  late final VideoWatermarkManager _watermarkManager;

  // Network monitoring
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  ConnectivityResult? _currentConnectivity;

  // Configuration
  NetworkPreference _globalNetworkPreference = NetworkPreference.any;
  bool _pauseOnMobileData = false;
  bool _isThrottlingEnabled = false;
  int _maxBytesPerSecond = 1024 * 1024; // 1 MB/s default

  // Stream controller for progress updates
  final StreamController<Map<String, dynamic>> _progressStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  // Getters
  Stream<Map<String, dynamic>> get progressStream =>
      _progressStreamController.stream;
  bool get isThrottlingEnabled => _isThrottlingEnabled;
  int get maxBytesPerSecond => _maxBytesPerSecond;
  NetworkPreference get globalNetworkPreference => _globalNetworkPreference;
  bool get pauseOnMobileData => _pauseOnMobileData;

  // Configuration setters
  set isThrottlingEnabled(bool value) {
    _isThrottlingEnabled = value;
    NyStorage.save('download_throttling_enabled', value);
    _downloadManager.updateThrottling(value, _maxBytesPerSecond);
  }

  set maxBytesPerSecond(int value) {
    if (value > 0) {
      _maxBytesPerSecond = value;
      NyStorage.save('download_max_bytes_per_second', value);
      _downloadManager.updateThrottling(_isThrottlingEnabled, value);
    }
  }

  set globalNetworkPreference(NetworkPreference value) {
    _globalNetworkPreference = value;
    NyStorage.save('network_preference', value.index);
    _checkNetworkAndUpdateQueue();
  }

  set pauseOnMobileData(bool value) {
    _pauseOnMobileData = value;
    NyStorage.save('pause_on_mobile_data', value);
    _checkNetworkAndUpdateQueue();
  }

  set maxConcurrentDownloads(int value) {
    if (value > 0) {
      _downloadManager.maxConcurrentDownloads = value;
      NyStorage.save('max_concurrent_downloads', value);
    }
  }

  // Initialize service
  Future<void> initialize() async {
    try {
      await _setCurrentUserContext();

      // Initialize managers
      _storageManager = VideoStorageManager();
      _watermarkManager = VideoWatermarkManager();
      _downloadManager = VideoDownloadManager(
        storageManager: _storageManager,
        watermarkManager: _watermarkManager,
        progressStreamController: _progressStreamController,
      );

      await _storageManager.initialize();
      await _watermarkManager.initialize();
      await _downloadManager.initialize();

      // Load settings
      await _loadSettings();

      // Set up network monitoring
      await _initializeNetworkMonitoring();

      // Check permissions
      bool hasPermission =
          await _storageManager.checkAndRequestStoragePermissions();
      if (!hasPermission) {
        NyLogger.info('Storage permissions not granted during initialization');
      }

      await _storageManager.cleanupOtherUsersData();
      await _downloadManager.restoreState();

      FirebaseCrashlytics.instance.log('VideoService initialized successfully');
      NyLogger.info('VideoService initialized successfully');
    } catch (e, stackTrace) {
      reportError('initialize', e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Network monitoring
  Future<void> _initializeNetworkMonitoring() async {
    try {
      List<ConnectivityResult> initialResults =
          await Connectivity().checkConnectivity();
      _currentConnectivity = initialResults.isNotEmpty
          ? initialResults.first
          : ConnectivityResult.none;

      _connectivitySubscription = Connectivity()
          .onConnectivityChanged
          .listen((List<ConnectivityResult> results) {
        _currentConnectivity =
            results.isNotEmpty ? results.first : ConnectivityResult.none;
        NyLogger.info('Network connectivity changed: $_currentConnectivity');
        _checkNetworkAndUpdateQueue();
      });

      NyLogger.info(
          'Network monitoring initialized, current: $_currentConnectivity');
    } catch (e) {
      NyLogger.error('Error initializing network monitoring: $e');
    }
  }

  void _checkNetworkAndUpdateQueue() {
    bool shouldPause = false;

    if (_currentConnectivity == ConnectivityResult.mobile) {
      if (_globalNetworkPreference == NetworkPreference.wifiOnly ||
          _pauseOnMobileData) {
        shouldPause = true;
      }
    }

    _downloadManager.handleNetworkChange(_currentConnectivity, shouldPause);
  }

  // Load saved settings
  Future<void> _loadSettings() async {
    try {
      dynamic throttlingEnabled =
          await NyStorage.read('download_throttling_enabled');
      if (throttlingEnabled is bool) {
        _isThrottlingEnabled = throttlingEnabled;
      }

      dynamic maxBytes = await NyStorage.read('download_max_bytes_per_second');
      if (maxBytes is int && maxBytes > 0) {
        _maxBytesPerSecond = maxBytes;
      }

      dynamic networkPrefIndex = await NyStorage.read('network_preference');
      if (networkPrefIndex is int &&
          networkPrefIndex >= 0 &&
          networkPrefIndex < NetworkPreference.values.length) {
        _globalNetworkPreference = NetworkPreference.values[networkPrefIndex];
      }

      dynamic pauseOnMobile = await NyStorage.read('pause_on_mobile_data');
      if (pauseOnMobile is bool) {
        _pauseOnMobileData = pauseOnMobile;
      }

      dynamic maxConcurrent = await NyStorage.read('max_concurrent_downloads');
      if (maxConcurrent is int && maxConcurrent > 0) {
        _downloadManager.maxConcurrentDownloads = maxConcurrent;
      }

      // Update download manager with loaded settings
      _downloadManager.updateThrottling(
          _isThrottlingEnabled, _maxBytesPerSecond);

      NyLogger.info('Settings loaded successfully');
    } catch (e) {
      NyLogger.error('Error loading settings: $e');
    }
  }

  Future<void> _setCurrentUserContext() async {
    try {
      var user = await Auth.data();
      if (user != null) {
        String userId = user['id']?.toString() ?? 'unknown';
        FirebaseCrashlytics.instance.setUserIdentifier(userId);
        FirebaseCrashlytics.instance
            .setCustomKey('user_email', user['email'] ?? 'unknown');
        FirebaseCrashlytics.instance.setCustomKey('current_user_id', userId);
      }
    } catch (e) {
      reportError('set_current_user_context', e);
    }
  }

  // Download operations
  Future<bool> enqueueDownload({
    required String videoUrl,
    required String courseId,
    required String videoId,
    required String watermarkText,
    String email = "",
    required Course course,
    required List<dynamic> curriculum,
    int priority = 100,
    NetworkPreference? networkPreference,
  }) async {
    return await _downloadManager.enqueueDownload(
      videoUrl: videoUrl,
      courseId: courseId,
      videoId: videoId,
      watermarkText: watermarkText,
      email: email,
      course: course,
      curriculum: curriculum,
      priority: priority,
      networkPreference: networkPreference ?? _globalNetworkPreference,
    );
  }

  Future<bool> downloadAllVideos({
    required String courseId,
    required Course course,
    required List<dynamic> curriculum,
    required String watermarkText,
    String email = "",
    NetworkPreference? networkPreference,
  }) async {
    return await _downloadManager.downloadAllVideos(
      courseId: courseId,
      course: course,
      curriculum: curriculum,
      watermarkText: watermarkText,
      email: email,
      networkPreference: networkPreference ?? _globalNetworkPreference,
    );
  }

  Future<bool> pauseDownload(
      {required String courseId, required String videoId}) async {
    return await _downloadManager.pauseDownload(
        courseId: courseId, videoId: videoId);
  }

  Future<bool> resumeDownload(
      {required String courseId, required String videoId}) async {
    return await _downloadManager.resumeDownload(
        courseId: courseId, videoId: videoId);
  }

  Future<bool> cancelDownload(
      {required String courseId, required String videoId}) async {
    return await _downloadManager.cancelDownload(
        courseId: courseId, videoId: videoId);
  }

  Future<bool> prioritizeDownload(
      {required String courseId, required String videoId}) async {
    return await _downloadManager.prioritizeDownload(
        courseId: courseId, videoId: videoId);
  }

  Future<bool> deleteVideo(
      {required String courseId, required String videoId}) async {
    return await _storageManager.deleteVideo(
        courseId: courseId, videoId: videoId);
  }

  // Status checking methods
  double getProgress(String courseId, String videoId) {
    return _downloadManager.getProgress(courseId, videoId);
  }

  bool isDownloading(String courseId, String videoId) {
    return _downloadManager.isDownloading(courseId, videoId);
  }

  bool isWatermarking(String courseId, String videoId) {
    return _downloadManager.isWatermarking(courseId, videoId);
  }

  bool isQueued(String courseId, String videoId) {
    return _downloadManager.isQueued(courseId, videoId);
  }

  bool isPaused(String courseId, String videoId) {
    return _downloadManager.isPaused(courseId, videoId);
  }

  String getDownloadSpeed(String courseId, String videoId) {
    return _downloadManager.getDownloadSpeed(courseId, videoId);
  }

  String getEstimatedTimeRemaining(String courseId, String videoId) {
    return _downloadManager.getEstimatedTimeRemaining(courseId, videoId);
  }

  VideoDownloadStatus getDetailedStatus(String courseId, String videoId) {
    return _downloadManager.getDetailedStatus(courseId, videoId);
  }

  int get queuedItemsCount => _downloadManager.queuedItemsCount;
  int get activeDownloadsCount => _downloadManager.activeDownloadsCount;

  Future<bool> isVideoDownloaded({
    required String videoUrl,
    required String courseId,
    required String videoId,
  }) async {
    return await _storageManager.isVideoFullyDownloaded(
      videoUrl: videoUrl,
      courseId: courseId,
      videoId: videoId,
    );
  }

  Future<bool> isVideoWatermarked(String courseId, String videoId) async {
    return await _watermarkManager.isVideoWatermarked(courseId, videoId);
  }

  // Backward compatibility methods - delegate to appropriate managers
  Future<bool> checkAndRequestStoragePermissions() async {
    return await _storageManager.checkAndRequestStoragePermissions();
  }

  Future<String> getVideoFilePath(String courseId, String videoId) async {
    return await _storageManager.getVideoFilePath(courseId, videoId);
  }

  Future<bool> checkStoragePermissions() async {
    return await _storageManager.checkAndRequestStoragePermissions();
  }

  Future<bool> requestStoragePermissions() async {
    return await _storageManager.checkAndRequestStoragePermissions();
  }

  Future<PermissionStatus> getStoragePermissionStatus() async {
    try {
      bool hasPermission =
          await _storageManager.checkAndRequestStoragePermissions();
      return hasPermission ? PermissionStatus.granted : PermissionStatus.denied;
    } catch (e) {
      return PermissionStatus.denied;
    }
  }

  Future<void> handlePermissionResult(
      BuildContext context, bool granted, PermissionStatus status) async {
    if (!granted) {
      if (status.isPermanentlyDenied) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Permission Required'),
            content: Text(
                'Storage permission has been permanently denied. Please enable it in app settings to download videos.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  openAppSettings();
                },
                child: Text('Open Settings'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Storage permission is required to download videos.'),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () async {
                bool newResult = await checkAndRequestStoragePermissions();
                if (newResult) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(
                            'Permission granted! You can now download videos.')),
                  );
                }
              },
            ),
          ),
        );
      }
    }
  }

  // Additional backward compatibility methods
  Future<bool> isVideoFullyDownloaded({
    required String videoUrl,
    required String courseId,
    required String videoId,
  }) async {
    return await _storageManager.isVideoFullyDownloaded(
      videoUrl: videoUrl,
      courseId: courseId,
      videoId: videoId,
    );
  }

  Future<VideoStatus> getVideoStatus({
    required String courseId,
    required String videoId,
  }) async {
    return await _storageManager.getVideoStatus(
      courseId: courseId,
      videoId: videoId,
      isDownloading: isDownloading,
      isWatermarking: isWatermarking,
      isQueued: isQueued,
    );
  }

  Future<bool> ensureVideoWatermarked({
    required String courseId,
    required String videoId,
    required String email,
    required String userName,
  }) async {
    return await _watermarkManager.ensureVideoWatermarked(
      courseId: courseId,
      videoId: videoId,
      email: email,
      userName: userName,
    );
  }

  Future<DownloadPermission> canDownloadVideo({
    required String courseId,
    required String videoId,
  }) async {
    return await _storageManager.canDownloadVideo(
      courseId: courseId,
      videoId: videoId,
    );
  }

  Future<bool> checkDiskSpace() async {
    return await _storageManager.checkDiskSpace();
  }

  Future<void> saveVideoMetadata({
    required String courseId,
    required String videoId,
    required int fileSize,
    required String watermarkText,
    required bool isWatermarked,
  }) async {
    await _storageManager.saveVideoMetadata(
      courseId: courseId,
      videoId: videoId,
      fileSize: fileSize,
      watermarkText: watermarkText,
      isWatermarked: isWatermarked,
    );
  }

  String getUserSpecificKey(String baseKey) {
    return _storageManager.getUserSpecificKey(baseKey);
  }

  // Play video
  Future<void> playVideo({
    required String videoUrl,
    required String courseId,
    required String videoId,
    required String watermarkText,
    required Course course,
    required BuildContext context,
  }) async {
    try {
      FirebaseCrashlytics.instance.setCustomKey('play_course_id', courseId);
      FirebaseCrashlytics.instance.setCustomKey('play_video_id', videoId);

      // Check subscription
      if (!course.hasValidSubscription) {
        await _showSubscriptionExpiredDialog(context, course);
        return;
      }

      String videoPath =
          await _storageManager.getVideoFilePath(courseId, videoId);
      bool isFullyDownloaded = await _storageManager.isVideoFullyDownloaded(
        videoUrl: videoUrl,
        courseId: courseId,
        videoId: videoId,
      );

      if (isFullyDownloaded) {
        await _playLocalVideo(
            context, courseId, videoId, videoPath, watermarkText);
      } else {
        await _handleVideoNotFound(
            context, videoUrl, courseId, videoId, watermarkText, course);
      }
    } catch (e, stackTrace) {
      reportError('playVideo', e, stackTrace: stackTrace);
      _showErrorSnackBar(context, "Failed to play video: ${e.toString()}");
    }
  }

  Future<void> _playLocalVideo(BuildContext context, String courseId,
      String videoId, String videoPath, String watermarkText) async {
    _showLoadingDialog(context, "Preparing video...");

    try {
      String email = "";
      String userName = "User";
      var user = await Auth.data();
      if (user != null) {
        email = user['email'] ?? '';
        userName = user['full_name'] ?? 'User';
      }

      String videoTitle = await _getVideoTitle(courseId, videoId);
      bool hasWatermark = await _watermarkManager.ensureVideoWatermarked(
        courseId: courseId,
        videoId: videoId,
        email: email,
        userName: userName,
      );

      Navigator.of(context, rootNavigator: true).pop(); // Remove loading dialog

      if (!hasWatermark) {
        _showWarningSnackBar(
            context, "Warning: Video may not be properly watermarked");
      }

      routeTo(VideoPlayerPage.path, data: {
        'videoPath': videoPath,
        'title': videoTitle,
      });
    } catch (e) {
      Navigator.of(context, rootNavigator: true).pop();
      _showErrorSnackBar(context, "Failed to prepare video: ${e.toString()}");
    }
  }

  Future<void> _handleVideoNotFound(
      BuildContext context,
      String videoUrl,
      String courseId,
      String videoId,
      String watermarkText,
      Course course) async {
    _showWarningSnackBar(context, "Please download the video first");

    bool shouldDownload =
        await _showDownloadConfirmationDialog(context) ?? false;
    if (shouldDownload) {
      var user = await Auth.data();
      String email = user?['email'] ?? '';

      await enqueueDownload(
        videoUrl: videoUrl,
        courseId: courseId,
        videoId: videoId,
        watermarkText: watermarkText,
        email: email,
        course: course,
        curriculum: course.curriculum,
        priority: 10,
      );

      _showSuccessSnackBar(
          context, "Download started. The video will be available soon.");
    }
  }

  // UI Helper methods
  Future<void> _showSubscriptionExpiredDialog(
      BuildContext context, Course course) async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(trans("Subscription Expired")),
          content: Text(trans(
              "Your subscription for this course has expired. Would you like to renew it?")),
          actions: [
            TextButton(
              child: Text(trans("Cancel")),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: Text(trans("Renew")),
              style: TextButton.styleFrom(foregroundColor: Colors.amber),
              onPressed: () async {
                Navigator.of(context).pop();
                routeTo(EnrollmentPlanPage.path, data: {
                  'curriculum': course.curriculum,
                  'course': course,
                  'isRenewal': true
                });
              },
            ),
          ],
        );
      },
    );
  }

  void _showLoadingDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 16),
              Text(message, style: const TextStyle(color: Colors.white)),
            ],
          ),
        );
      },
    );
  }

  Future<bool?> _showDownloadConfirmationDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(trans("Video Not Found")),
        content: Text(trans("Would you like to download this video now?")),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(trans("No")),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(trans("Yes")),
          ),
        ],
      ),
    );
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(trans(message)),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showWarningSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(trans(message)),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccessSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(trans(message)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<String> _getVideoTitle(String courseId, String videoId) async {
    try {
      String title = await _storageManager.getVideoTitle(courseId, videoId);
      return title.isNotEmpty ? title : "Video $videoId";
    } catch (e) {
      return "Video $videoId";
    }
  }

  // Cleanup methods
  Future<void> handleUserLogout() async {
    try {
      await _downloadManager.handleUserLogout();
      FirebaseCrashlytics.instance.setUserIdentifier('logged_out');
      NyLogger.info('User logout handled successfully');
    } catch (e, stackTrace) {
      reportError('handle_user_logout', e, stackTrace: stackTrace);
    }
  }

  Future<void> handleUserLogin() async {
    try {
      await _setCurrentUserContext();
      await _storageManager.cleanupOtherUsersData();
      await _downloadManager.restoreState();
      NyLogger.info('User login handled successfully');
    } catch (e, stackTrace) {
      reportError('handle_user_login', e, stackTrace: stackTrace);
    }
  }

  Future<int> cleanupStaleDownloads({required String courseId}) async {
    return await _downloadManager.cleanupStaleDownloads(courseId: courseId);
  }

  void dispose() {
    try {
      _connectivitySubscription.cancel();
      _downloadManager.dispose();
      _watermarkManager.dispose();
      _storageManager.dispose();

      if (!_progressStreamController.isClosed) {
        _progressStreamController.close();
      }

      NyLogger.info('VideoService disposed successfully');
    } catch (e, stackTrace) {
      reportError('dispose', e, stackTrace: stackTrace);
    }
  }
}
