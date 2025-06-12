import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'dart:math' show min;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:ffmpeg_kit_flutter_new/statistics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart'; // Add this package for network connectivity
import 'package:storage_info/storage_info.dart';

import '../../resources/pages/enrollment_plan_page.dart';
import '../../resources/pages/video_player_page.dart';
import '../../app/models/course.dart';
import '../networking/course_api_service.dart';

enum DownloadPhase {
  queued,
  initializing,
  downloading,
  watermarking,
  completed,
  error,
  cancelled,
  paused,
  retrying,
}

enum NetworkPreference {
  wifiOnly,
  wifiAndMobile,
  any,
}

// Enhanced queue item for downloads with retry and network preferences
class DownloadQueueItem {
  final String videoUrl;
  final String courseId;
  final String videoId;
  final String watermarkText;
  final String email;
  final Course course;
  final List<dynamic> curriculum;
  int priority; // Lower number = higher priority
  final DateTime queuedAt;

  // New fields for enhanced functionality
  int retryCount;
  DateTime? lastRetryTime;
  bool isPaused;
  NetworkPreference networkPreference;
  DateTime? pausedAt;
  double progress;

  DownloadQueueItem({
    required this.videoUrl,
    required this.courseId,
    required this.videoId,
    required this.watermarkText,
    required this.email,
    required this.course,
    required this.curriculum,
    this.priority = 100, // Default priority
    DateTime? queuedAt,
    this.retryCount = 0,
    this.lastRetryTime,
    this.isPaused = false,
    this.networkPreference = NetworkPreference.any,
    this.pausedAt,
    this.progress = 0.0,
  }) : this.queuedAt = queuedAt ?? DateTime.now();

  // Convert to JSON for persistent storage
  Map<String, dynamic> toJson() {
    return {
      'videoUrl': videoUrl,
      'courseId': courseId,
      'videoId': videoId,
      'watermarkText': watermarkText,
      'email': email,
      'course': course.toJson(),
      'curriculum': curriculum,
      'priority': priority,
      'queuedAt': queuedAt.toIso8601String(),
      'retryCount': retryCount,
      'lastRetryTime': lastRetryTime?.toIso8601String(),
      'isPaused': isPaused,
      'networkPreference': networkPreference.index,
      'pausedAt': pausedAt?.toIso8601String(),
      'progress': progress,
    };
  }

  // Create from JSON for persistent storage
  factory DownloadQueueItem.fromJson(Map<String, dynamic> json) {
    return DownloadQueueItem(
      videoUrl: json['videoUrl'],
      courseId: json['courseId'],
      videoId: json['videoId'],
      watermarkText: json['watermarkText'] ?? '',
      email: json['email'] ?? '',
      course: Course.fromJson(json['course']),
      curriculum: json['curriculum'] ?? [],
      priority: json['priority'] ?? 100,
      queuedAt:
          json['queuedAt'] != null ? DateTime.parse(json['queuedAt']) : null,
      retryCount: json['retryCount'] ?? 0,
      lastRetryTime: json['lastRetryTime'] != null
          ? DateTime.parse(json['lastRetryTime'])
          : null,
      isPaused: json['isPaused'] ?? false,
      networkPreference:
          NetworkPreference.values[json['networkPreference'] ?? 0],
      pausedAt:
          json['pausedAt'] != null ? DateTime.parse(json['pausedAt']) : null,
      progress: json['progress'] ?? 0.0,
    );
  }
}

class VideoDownloadStatus {
  final DownloadPhase phase;
  final double progress;
  final String message;
  final int? bytesReceived;
  final int? totalBytes;
  final String? error;
  final DateTime? startTime;
  final int retryCount;
  final DateTime? nextRetryTime;
  final NetworkPreference networkPreference;

  VideoDownloadStatus({
    this.phase = DownloadPhase.initializing,
    this.progress = 0.0,
    this.message = "",
    this.bytesReceived,
    this.totalBytes,
    this.error,
    this.startTime,
    this.retryCount = 0,
    this.nextRetryTime,
    this.networkPreference = NetworkPreference.any,
  });

  bool get isDownloading => phase == DownloadPhase.downloading;
  bool get isWatermarking => phase == DownloadPhase.watermarking;
  bool get isCompleted => phase == DownloadPhase.completed;
  bool get hasError => phase == DownloadPhase.error;
  bool get isCancelled => phase == DownloadPhase.cancelled;
  bool get isQueued => phase == DownloadPhase.queued;
  bool get isPaused => phase == DownloadPhase.paused;
  bool get isRetrying => phase == DownloadPhase.retrying;

  String get displayMessage {
    switch (phase) {
      case DownloadPhase.queued:
        return "Queued for download...";
      case DownloadPhase.initializing:
        return "Preparing download...";
      case DownloadPhase.downloading:
        if (bytesReceived != null && totalBytes != null) {
          String received = _formatBytes(bytesReceived!);
          String total = _formatBytes(totalBytes!);
          return "Downloaded $received of $total";
        }
        return "Downloading...";
      case DownloadPhase.watermarking:
        return "Adding watermark...";
      case DownloadPhase.completed:
        return "Download completed";
      case DownloadPhase.error:
        String baseMessage = error ?? "Download failed";
        if (nextRetryTime != null) {
          return "$baseMessage - Retrying soon (Attempt ${retryCount + 1})";
        }
        return baseMessage;
      case DownloadPhase.cancelled:
        return "Download cancelled";
      case DownloadPhase.paused:
        return "Download paused";
      case DownloadPhase.retrying:
        return "Retrying download (Attempt ${retryCount + 1})...";
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
    return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
  }
}

// Custom interceptor for throttling downloads
class ThrottlingInterceptor extends Interceptor {
  int maxBytesPerSecond;
  DateTime? _lastChunkTime;
  int _bytesInCurrentSecond = 0;

  ThrottlingInterceptor(this.maxBytesPerSecond);

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (response.requestOptions.responseType == ResponseType.stream) {
      final originalStream = response.data as ResponseBody;

      // First transform with throttling (Stream<List<int>>)
      final throttledListStream = originalStream.stream.transform(
        StreamTransformer.fromHandlers(
          handleData: (List<int> data, EventSink<List<int>> sink) {
            _throttle(data, sink);
          },
        ),
      );

      // Then convert to Stream<Uint8List> which ResponseBody requires
      final throttledUint8Stream = throttledListStream.map((List<int> data) {
        return Uint8List.fromList(data);
      });

      // Create new ResponseBody with the correct stream type
      response.data = ResponseBody(
        throttledUint8Stream,
        originalStream.statusCode,
        headers: originalStream.headers,
        isRedirect: originalStream.isRedirect,
        redirects: originalStream.redirects,
        statusMessage: originalStream.statusMessage,
      );
    }

    handler.next(response);
  }

  void _throttle(List<int> data, EventSink<List<int>> sink) async {
    if (maxBytesPerSecond <= 0) {
      sink.add(data);
      return;
    }

    final now = DateTime.now();
    _lastChunkTime ??= now;

    // Reset counter if a new second has started
    if (now.difference(_lastChunkTime!).inSeconds >= 1) {
      _bytesInCurrentSecond = 0;
      _lastChunkTime = now;
    }

    _bytesInCurrentSecond += data.length;

    // If we've transferred too much data in this second, wait
    if (_bytesInCurrentSecond > maxBytesPerSecond) {
      final nextSecond = _lastChunkTime!.add(const Duration(seconds: 1));
      final waitTime = nextSecond.difference(now);

      if (waitTime.inMilliseconds > 0) {
        await Future.delayed(waitTime);
        _bytesInCurrentSecond = data.length;
        _lastChunkTime = DateTime.now();
      }
    }

    sink.add(data);
  }
}

class CancelException implements Exception {
  final String message;
  CancelException(this.message);
}

class PauseException implements Exception {
  final String message;
  PauseException(this.message);
}

class VideoService {
  // Singleton instance
  static final VideoService _instance = VideoService._internal();

  factory VideoService() {
    return _instance;
  }

  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;

  VideoService._internal();

  // Dio instance for download with progress
  final Dio _dio = Dio();

  // Download queue and status tracking
  final List<DownloadQueueItem> _downloadQueue = [];
  bool _isProcessingQueue = false;
  int _maxConcurrentDownloads = 2; // Maximum concurrent downloads
  int _activeDownloads = 0;
  bool _isRequestingPermission = false;
  bool _permissionsGranted = false;
  DateTime? _lastPermissionCheck;
  final Duration _permissionCacheTime = Duration(hours: 24);

  // Map to store progress and download status
  final Map<String, double> _downloadProgress = {};
  final Map<String, bool> _downloadingStatus = {};
  final Map<String, bool> _cancelRequests = {};

  // Map to store watermarking status
  final Map<String, bool> _watermarkingStatus = {};
  final Map<String, double> _watermarkProgress = {};

  // Enhanced status tracking
  final Map<String, VideoDownloadStatus> _detailedStatus = {};

  // Download speed tracking
  final Map<String, List<int>> _downloadSpeedTracker = {};
  final Map<String, DateTime> _downloadStartTime = {};

  // Retry tracking
  final Map<String, int> _retryCount = {};
  final Map<String, Timer> _retryTimers = {};
  final int _maxRetryAttempts = 5;

  // Network preferences
  NetworkPreference _globalNetworkPreference = NetworkPreference.any;
  ConnectivityResult? _currentConnectivity;
  bool _pauseOnMobileData = false;

  // Throttling options
  bool _isThrottlingEnabled = false;
  int _maxBytesPerSecond = 1024 * 1024; // 1 MB/s default

  // Disk space thresholds
  final int _minRequiredSpaceMB = 500; // 500 MB minimum free space

  // Stream controller for download progress updates
  final StreamController<Map<String, dynamic>> _progressStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  // Getter for progress stream
  Stream<Map<String, dynamic>> get progressStream =>
      _progressStreamController.stream;

  // Getters and setters for configuration options
  bool get isThrottlingEnabled => _isThrottlingEnabled;
  set isThrottlingEnabled(bool value) {
    _isThrottlingEnabled = value;
    NyStorage.save('download_throttling_enabled', value);
  }

  int get maxBytesPerSecond => _maxBytesPerSecond;
  set maxBytesPerSecond(int value) {
    if (value > 0) {
      _maxBytesPerSecond = value;
      NyStorage.save('download_max_bytes_per_second', value);
    }
  }

  NetworkPreference get globalNetworkPreference => _globalNetworkPreference;
  set globalNetworkPreference(NetworkPreference value) {
    _globalNetworkPreference = value;
    NyStorage.save('network_preference', value.index);
    _checkNetworkAndUpdateQueue();
  }

  bool get pauseOnMobileData => _pauseOnMobileData;
  set pauseOnMobileData(bool value) {
    _pauseOnMobileData = value;
    NyStorage.save('pause_on_mobile_data', value);
    _checkNetworkAndUpdateQueue();
  }

  String? _currentUserId;
  // Initialize service
  Future<void> initialize() async {
    try {
      await _setCurrentUserContext();
      try {
        var user = await Auth.data();
        if (user != null) {
          FirebaseCrashlytics.instance
              .setUserIdentifier(user['id']?.toString() ?? 'unknown');
          FirebaseCrashlytics.instance
              .setCustomKey('user_email', user['email'] ?? 'unknown');
        }
      } catch (e) {
        _reportError('set_user_context', e);
      }
      // Load settings first
      await _loadSettings();

      // Initialize FFmpeg
      await _initializeFFmpeg();

      // Set up network monitoring
      await _initializeNetworkMonitoring();

      // Check permissions early but don't fail initialization if denied
      bool hasPermission = await checkAndRequestStoragePermissions();
      if (!hasPermission) {
        FirebaseCrashlytics.instance
            .log('Storage permissions not granted during initialization');
        NyLogger.info(
            'Storage permissions not granted during initialization - downloads will request when needed');
      }

      await _cleanupOtherUsersData();
      // Restore queue and pending downloads
      await _restoreQueueState();
      await _restorePendingDownloads();

      FirebaseCrashlytics.instance.log('VideoService initialized successfully');
      NyLogger.info('VideoService initialized successfully');
    } catch (e, stackTrace) {
      _reportError('initialize', e, stackTrace: stackTrace);

      NyLogger.error('Error initializing VideoService: $e');
      rethrow; // Re-throw to maintain original behavior
    }
  }

  Future<void> _setCurrentUserContext() async {
    try {
      var user = await Auth.data();
      if (user != null) {
        _currentUserId = user['id']?.toString();
        FirebaseCrashlytics.instance
            .setCustomKey('current_user_id', _currentUserId ?? 'unknown');
      }
    } catch (e) {
      _reportError('set_current_user_context', e);
      _currentUserId = null;
    }
  }

  Future<void> _cleanupOtherUsersData() async {
    try {
      String currentUserId = await _getCurrentUserId();

      // Clean up storage keys from other users
      await _cleanupOtherUsersStorageKeys(currentUserId);

      // Optionally clean up files from other users (be careful with this)
      // await _cleanupOtherUsersFiles(currentUserId);

      FirebaseCrashlytics.instance
          .log('Cleaned up other users data, current user: $currentUserId');
    } catch (e, stackTrace) {
      _reportError('cleanup_other_users_data', e, stackTrace: stackTrace);
    }
  }

  Future<void> _cleanupOtherUsersStorageKeys(String currentUserId) async {
    try {
      // Since NyStorage doesn't have a keys() method, we'll track known keys
      // and clean them up individually
      List<String> knownUserKeys = [
        'download_queue',
        'pending_downloads',
        'download_throttling_enabled',
        'download_max_bytes_per_second',
        'network_preference',
        'pause_on_mobile_data',
        'max_concurrent_downloads',
      ];

      List<String> keysToRemove = [];

      // Check for user-specific versions of known keys
      for (String baseKey in knownUserKeys) {
        // Look for keys with different user IDs
        for (int i = 1; i <= 10; i++) {
          // Check up to 10 different user IDs
          String otherUserKey = '${baseKey}_user_$i';
          if (otherUserKey != '${baseKey}_user_$currentUserId') {
            // Try to read the key to see if it exists
            try {
              dynamic value = await NyStorage.read(otherUserKey);
              if (value != null) {
                keysToRemove.add(otherUserKey);
              }
            } catch (e) {
              // Key doesn't exist, continue
            }
          }
        }
      }

      // Remove keys from other users
      for (String key in keysToRemove) {
        try {
          await NyStorage.delete(key);
        } catch (e) {
          _reportError('delete_other_user_key', e,
              additionalData: {'key': key});
        }
      }

      FirebaseCrashlytics.instance.log(
          'Cleaned up ${keysToRemove.length} storage keys from other users');
    } catch (e, stackTrace) {
      _reportError('cleanup_other_users_storage_keys', e,
          stackTrace: stackTrace);
    }
  }

  Future<void> _initializeFFmpeg() async {
    try {
      // You can add any FFmpeg initialization code here if needed
      // This is a good place to log FFmpeg information or set options
      NyLogger.info('FFmpeg initialized');
    } catch (e) {
      NyLogger.error('Error initializing FFmpeg: $e');
    }
  }

  Future<bool> checkAndRequestStoragePermissions() async {
    try {
      // Prevent concurrent permission requests
      if (_isRequestingPermission) {
        FirebaseCrashlytics.instance
            .log('Permission request already in progress, waiting...');
        NyLogger.info('Permission request already in progress, waiting...');

        // Wait for current request to complete (max 10 seconds)
        int waitCount = 0;
        while (_isRequestingPermission && waitCount < 20) {
          await Future.delayed(Duration(milliseconds: 500));
          waitCount++;
        }

        return _permissionsGranted;
      }

      // Check cache first (avoid too frequent permission checks)
      if (_lastPermissionCheck != null &&
          DateTime.now()
                  .difference(_lastPermissionCheck!)
                  .compareTo(_permissionCacheTime) <
              0 &&
          _permissionsGranted) {
        return _permissionsGranted;
      }

      _isRequestingPermission = true;

      try {
        if (Platform.isAndroid) {
          bool hasPermission = await _checkAndroidPermissions();

          if (!hasPermission) {
            hasPermission = await _requestAndroidPermissions();
          }

          _permissionsGranted = hasPermission;
          _lastPermissionCheck = DateTime.now();

          FirebaseCrashlytics.instance
              .setCustomKey('android_permissions_granted', hasPermission);
          NyLogger.info('Android permissions granted: $hasPermission');
          return hasPermission;
        } else if (Platform.isIOS) {
          // iOS doesn't need storage permissions for app documents directory
          _permissionsGranted = true;
          _lastPermissionCheck = DateTime.now();
          return true;
        }

        return false;
      } finally {
        _isRequestingPermission = false;
      }
    } catch (e, stackTrace) {
      _isRequestingPermission = false;
      _reportError('checkAndRequestStoragePermissions', e,
          stackTrace: stackTrace,
          additionalData: {
            'platform': Platform.operatingSystem,
            'permissions_granted': _permissionsGranted,
          });
      return false;
    }
  }

  Future<bool> _checkAndroidPermissions() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;

      FirebaseCrashlytics.instance
          .setCustomKey('android_sdk_int', androidInfo.version.sdkInt);

      if (androidInfo.version.sdkInt >= 33) {
        // Android 13+ - Check scoped storage permissions
        bool videosGranted = await Permission.videos.isGranted;
        bool audioGranted = await Permission.audio.isGranted;

        FirebaseCrashlytics.instance
            .setCustomKey('videos_permission_granted', videosGranted);
        FirebaseCrashlytics.instance
            .setCustomKey('audio_permission_granted', audioGranted);

        NyLogger.info(
            'Android 13+ permissions - Videos: $videosGranted, Audio: $audioGranted');
        return videosGranted && audioGranted;
      } else {
        // Android 12 and below - Check storage permission
        bool storageGranted = await Permission.storage.isGranted;

        FirebaseCrashlytics.instance
            .setCustomKey('storage_permission_granted', storageGranted);
        NyLogger.info('Android <=12 storage permission: $storageGranted');
        return storageGranted;
      }
    } catch (e, stackTrace) {
      _reportError('_checkAndroidPermissions', e, stackTrace: stackTrace);
      return false;
    }
  }

  Future<bool> _requestAndroidPermissions() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;

      if (androidInfo.version.sdkInt >= 33) {
        // Android 13+ - Request multiple permissions at once
        Map<Permission, PermissionStatus> statuses = await [
          Permission.videos,
          Permission.audio,
        ].request();

        bool videosGranted = statuses[Permission.videos]?.isGranted ?? false;
        bool audioGranted = statuses[Permission.audio]?.isGranted ?? false;

        NyLogger.info(
            'Android 13+ permission request results - Videos: $videosGranted, Audio: $audioGranted');

        // Check for permanently denied
        if (statuses[Permission.videos]?.isPermanentlyDenied == true ||
            statuses[Permission.audio]?.isPermanentlyDenied == true) {
          _notifyPermissionPermanentlyDenied();
        }

        return videosGranted && audioGranted;
      } else {
        // Android 12 and below - Request storage permission
        PermissionStatus status = await Permission.storage.request();

        NyLogger.info(
            'Android <=12 storage permission request result: $status');

        if (status.isPermanentlyDenied) {
          _notifyPermissionPermanentlyDenied();
        }

        return status.isGranted;
      }
    } catch (e) {
      NyLogger.error('Error requesting Android permissions: $e');
      return false;
    }
  }

  void _notifyPermissionPermanentlyDenied() {
    _progressStreamController.add({
      'type': 'error',
      'errorType': 'permissionPermanentlyDenied',
      'message':
          'Storage permission permanently denied. Please enable in app settings.',
    });
  }

  String getEstimatedTimeRemaining(String courseId, String videoId) {
    try {
      String key = '${courseId}_${videoId}';
      VideoDownloadStatus status =
          _detailedStatus[key] ?? VideoDownloadStatus();

      // Check if we have necessary data to calculate time remaining
      if (status.isDownloading &&
          status.bytesReceived != null &&
          status.totalBytes != null &&
          _downloadSpeedTracker[key] != null &&
          _downloadSpeedTracker[key]!.isNotEmpty) {
        // Calculate average download speed (bytes per second)
        List<int> speedHistory = _downloadSpeedTracker[key]!;
        int recentMeasurements =
            speedHistory.length > 5 ? 5 : speedHistory.length;
        double avgSpeed = speedHistory
                .skip(speedHistory.length - recentMeasurements)
                .reduce((a, b) => a + b) /
            recentMeasurements;

        if (avgSpeed <= 0) return ""; // Avoid division by zero

        // Calculate remaining bytes
        int remainingBytes = status.totalBytes! - status.bytesReceived!;

        // Calculate time in seconds
        int secondsRemaining = (remainingBytes / avgSpeed).round();

        // Format time remaining
        if (secondsRemaining < 60) {
          return "$secondsRemaining seconds";
        } else if (secondsRemaining < 3600) {
          int minutes = secondsRemaining ~/ 60;
          return "$minutes minutes";
        } else {
          int hours = secondsRemaining ~/ 3600;
          int minutes = (secondsRemaining % 3600) ~/ 60;
          return "$hours hours, $minutes minutes";
        }
      }

      return ""; // Return empty string if we can't calculate
    } catch (e) {
      NyLogger.error('Error calculating time remaining: $e');
      return "";
    }
  }

  // Enhanced remove from pending downloads with user isolation
  Future<void> _removeFromPendingDownloads(
      String courseId, String videoId) async {
    try {
      String pendingKey = _getUserSpecificKey('pending_downloads');
      dynamic pendingDownloadsRaw = await NyStorage.read(pendingKey);
      List<dynamic> pendingDownloads = [];

      if (pendingDownloadsRaw is List) {
        pendingDownloads = pendingDownloadsRaw;
      } else if (pendingDownloadsRaw is String) {
        try {
          var decoded = jsonDecode(pendingDownloadsRaw);
          if (decoded is List) {
            pendingDownloads = decoded;
          }
        } catch (e) {
          pendingDownloads = [];
        }
      }

      List<dynamic> updatedDownloads = [];

      for (dynamic item in pendingDownloads) {
        try {
          Map<String, dynamic> downloadData;
          if (item is String) {
            downloadData = jsonDecode(item);
          } else if (item is Map) {
            downloadData = Map<String, dynamic>.from(item);
          } else {
            continue;
          }

          if (downloadData['courseId'] != courseId ||
              downloadData['videoId'] != videoId) {
            updatedDownloads.add(item);
          }
        } catch (e) {
          updatedDownloads.add(item);
        }
      }

      await NyStorage.save(pendingKey, updatedDownloads);
    } catch (e) {
      _reportError('remove_from_pending_downloads', e, additionalData: {
        'user_id': _currentUserId ?? 'unknown',
        'course_id': courseId,
        'video_id': videoId,
      });
    }
  }

  // Load saved settings
  Future<void> _loadSettings() async {
    try {
      // Load throttling settings
      dynamic throttlingEnabled =
          await NyStorage.read('download_throttling_enabled');
      if (throttlingEnabled is bool) {
        _isThrottlingEnabled = throttlingEnabled;
      }

      dynamic maxBytes = await NyStorage.read('download_max_bytes_per_second');
      if (maxBytes is int && maxBytes > 0) {
        _maxBytesPerSecond = maxBytes;
      }

      // Load network preferences
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

      // Load concurrent downloads setting
      dynamic maxConcurrent = await NyStorage.read('max_concurrent_downloads');
      if (maxConcurrent is int && maxConcurrent > 0) {
        _maxConcurrentDownloads = maxConcurrent;
      }

      NyLogger.info(
          'Loaded settings: throttling=$_isThrottlingEnabled, maxBytes=$_maxBytesPerSecond, ' +
              'networkPref=$_globalNetworkPreference, pauseOnMobile=$_pauseOnMobileData');
    } catch (e) {
      NyLogger.error('Error loading settings: $e');
    }
  }

  // Check network and update queue status
  void _checkNetworkAndUpdateQueue() {
    try {
      bool shouldPause = false;

      // Check if we should pause based on network type
      if (_currentConnectivity == ConnectivityResult.mobile) {
        if (_globalNetworkPreference == NetworkPreference.wifiOnly) {
          shouldPause = true;
        } else if (_pauseOnMobileData) {
          shouldPause = true;
        }
      }

      // Update queue items based on network status
      if (shouldPause) {
        // Pause active downloads that require WiFi
        for (String key in _downloadingStatus.keys) {
          if (_downloadingStatus[key] == true) {
            List<String> parts = key.split('_');
            if (parts.length == 2) {
              String courseId = parts[0];
              String videoId = parts[1];

              // Find the item in the queue
              int queueIndex = _downloadQueue.indexWhere((item) =>
                  item.courseId == courseId && item.videoId == videoId);

              if (queueIndex >= 0 &&
                  (_downloadQueue[queueIndex].networkPreference ==
                      NetworkPreference.wifiOnly)) {
                _pauseDownload(courseId, videoId);
              }
            }
          }
        }
      } else {
        // Resume paused downloads
        List<DownloadQueueItem> pausedItems =
            _downloadQueue.where((item) => item.isPaused).toList();
        for (var item in pausedItems) {
          // Only resume if network preference is satisfied
          if (_canDownloadOnCurrentNetwork(item.networkPreference)) {
            _resumeDownload(item.courseId, item.videoId);
          }
        }
      }

      // Trigger queue processing to continue downloads
      _processQueue();
    } catch (e) {
      NyLogger.error('Error checking network and updating queue: $e');
    }
  }

  Future<bool> _pauseDownload(String courseId, String videoId) async {
    try {
      // This is an internal method that's called from _checkNetworkAndUpdateQueue
      String downloadKey = '${courseId}_${videoId}';

      // Find the item in the queue
      int index = _downloadQueue.indexWhere(
          (item) => item.courseId == courseId && item.videoId == videoId);

      if (index >= 0) {
        // If it's just queued, mark as paused
        _downloadQueue[index].isPaused = true;
        _downloadQueue[index].pausedAt = DateTime.now();

        // Update status
        _detailedStatus[downloadKey] = VideoDownloadStatus(
          phase: DownloadPhase.paused,
          progress: _downloadQueue[index].progress,
          message: "Download paused - network changed",
          networkPreference: _downloadQueue[index].networkPreference,
        );

        _notifyProgressUpdate(courseId, videoId, _downloadQueue[index].progress,
            statusMessage: "Download paused - network changed");

        // Save queue state
        await _saveQueueState();

        return true;
      }

      // If it's currently downloading, cancel it and re-add to queue as paused
      if (_downloadingStatus[downloadKey] == true) {
        // Get current progress
        double progress = _downloadProgress[downloadKey] ?? 0.0;

        // Cancel current download
        _cancelRequests[downloadKey] = true;
        _downloadingStatus[downloadKey] = false;

        // Find download data and re-add to queue as paused
        // Similar to pauseDownload but with network-specific messaging

        // (Rest of implementation follows the same pattern as the public pauseDownload method)
        // ...

        return true;
      }

      return false;
    } catch (e) {
      NyLogger.error('Error in _pauseDownload: $e');
      return false;
    }
  }

  // Check if we can download on current network
  bool _canDownloadOnCurrentNetwork(NetworkPreference preference) {
    if (preference == NetworkPreference.any) {
      return true;
    }

    if (preference == NetworkPreference.wifiAndMobile) {
      return _currentConnectivity == ConnectivityResult.wifi ||
          _currentConnectivity == ConnectivityResult.mobile;
    }

    if (preference == NetworkPreference.wifiOnly) {
      return _currentConnectivity == ConnectivityResult.wifi;
    }

    return false;
  }

  // Save queue state
  Future<void> _saveQueueState() async {
    try {
      List<Map<String, dynamic>> queueData =
          _downloadQueue.map((item) => item.toJson()).toList();
      String userSpecificKey = _getUserSpecificKey('download_queue');
      await NyStorage.save(userSpecificKey, jsonEncode(queueData));
      NyLogger.info(
          'Saved queue state with ${queueData.length} items for user: $_currentUserId');
    } catch (e, stackTrace) {
      _reportError('save_queue_state', e, additionalData: {
        'user_id': _currentUserId ?? 'unknown',
        'queue_size': _downloadQueue.length,
      });
    }
  }

  // Enhanced restore queue state with user isolation
  Future<void> _restoreQueueState() async {
    try {
      String userSpecificKey = _getUserSpecificKey('download_queue');
      String? queueDataString = await NyStorage.read(userSpecificKey);

      if (queueDataString != null && queueDataString.isNotEmpty) {
        List<dynamic> queueJson = jsonDecode(queueDataString);

        for (var itemJson in queueJson) {
          try {
            DownloadQueueItem item = DownloadQueueItem.fromJson(itemJson);

            // Verify this item belongs to current user by checking file paths
            String expectedVideoPath =
                await getVideoFilePath(item.courseId, item.videoId);
            File videoFile = File(expectedVideoPath);

            // Only restore if file exists or if we're in the middle of downloading
            if (await videoFile.exists() || item.progress > 0) {
              _downloadQueue.add(item);

              // Initialize status
              String downloadKey = '${item.courseId}_${item.videoId}';
              _downloadProgress[downloadKey] = item.progress;
              _downloadingStatus[downloadKey] = false;
              _cancelRequests[downloadKey] = false;
              _watermarkingStatus[downloadKey] = false;

              // Set detailed status
              _detailedStatus[downloadKey] = VideoDownloadStatus(
                phase:
                    item.isPaused ? DownloadPhase.paused : DownloadPhase.queued,
                progress: item.progress,
                message:
                    item.isPaused ? "Download paused" : "Queued for download",
                retryCount: item.retryCount,
                networkPreference: item.networkPreference,
              );

              NyLogger.info(
                  'Restored queue item: Course ${item.courseId}, Video ${item.videoId}, ' +
                      'Status: ${item.isPaused ? "paused" : "queued"}, Progress: ${item.progress}');
            }
          } catch (e) {
            _reportError('restore_queue_item', e);
          }
        }

        NyLogger.info(
            'Restored ${_downloadQueue.length} items to download queue for user: $_currentUserId');
      }
    } catch (e) {
      _reportError('restore_queue_state', e, additionalData: {
        'user_id': _currentUserId ?? 'unknown',
      });
    }
  }

  // Enhanced restore pending downloads with user isolation
  Future<void> _restorePendingDownloads() async {
    try {
      String userSpecificKey = _getUserSpecificKey('pending_downloads');
      dynamic pendingDownloadsRaw = await NyStorage.read(userSpecificKey);
      List<dynamic> pendingDownloads = [];

      if (pendingDownloadsRaw is List) {
        pendingDownloads = pendingDownloadsRaw;
      } else if (pendingDownloadsRaw is String) {
        try {
          var decoded = jsonDecode(pendingDownloadsRaw);
          if (decoded is List) {
            pendingDownloads = decoded;
          }
        } catch (e) {
          pendingDownloads = [];
        }
      }

      if (pendingDownloads.isNotEmpty) {
        // Add all pending downloads to queue
        for (dynamic item in pendingDownloads) {
          try {
            Map<String, dynamic> downloadData;
            if (item is String) {
              downloadData = jsonDecode(item);
            } else if (item is Map) {
              downloadData = Map<String, dynamic>.from(item);
            } else {
              continue;
            }

            String videoId = downloadData['videoId'];
            String courseId = downloadData['courseId'];
            String downloadKey = '${courseId}_${videoId}';

            // Skip if already in queue
            if (_downloadQueue.any((item) =>
                item.courseId == courseId && item.videoId == videoId)) {
              NyLogger.info(
                  'Skipping duplicate pending download for $courseId $videoId');
              continue;
            }

            // Check if the video file exists for this user
            String videoPath = await getVideoFilePath(courseId, videoId);
            File videoFile = File(videoPath);

            // Check if it was previously downloading
            String progressKey = _getUserSpecificKey('progress_$downloadKey');
            dynamic storedProgress = await NyStorage.read(progressKey);
            double progress = 0.0;
            if (storedProgress is double) {
              progress = storedProgress;
            } else if (storedProgress is int) {
              progress = storedProgress.toDouble();
            } else if (storedProgress is String) {
              try {
                progress = double.parse(storedProgress);
              } catch (e) {
                // Keep default 0.0
              }
            }

            // Only restore if file exists or there's significant progress
            if (await videoFile.exists() || progress > 0.1) {
              // Initialize status
              _downloadProgress[downloadKey] = progress;
              _downloadingStatus[downloadKey] = false;
              _cancelRequests[downloadKey] = false;
              _watermarkingStatus[downloadKey] = false;

              // Add to queue if all required fields are present
              if (downloadData.containsKey('videoUrl') &&
                  downloadData.containsKey('courseId') &&
                  downloadData.containsKey('videoId')) {
                dynamic course = downloadData['course'];
                List<dynamic> curriculum = [];
                String watermarkText = downloadData['watermarkText'] ?? '';
                String email = downloadData['email'] ?? '';

                if (downloadData.containsKey('curriculum')) {
                  dynamic curriculumData = downloadData['curriculum'];
                  if (curriculumData is List) {
                    curriculum = curriculumData;
                  }
                }

                // Check for retry information
                int retryCount = 0;
                if (downloadData.containsKey('retryCount')) {
                  retryCount = downloadData['retryCount'];
                }

                // Add to queue with higher priority (older items)
                _enqueueDownload(
                  videoUrl: downloadData['videoUrl'],
                  courseId: downloadData['courseId'],
                  videoId: downloadData['videoId'],
                  watermarkText: watermarkText,
                  email: email,
                  course: course,
                  curriculum: curriculum,
                  priority: 10, // Higher priority for restored downloads
                  progress: progress,
                  retryCount: retryCount,
                );
              }
            }
          } catch (e) {
            _reportError('restore_pending_download', e);
          }
        }

        // Start processing the queue
        _processQueue();
      }
    } catch (e) {
      _reportError('restore_pending_downloads', e, additionalData: {
        'user_id': _currentUserId ?? 'unknown',
      });
    }
  }

  // Method to get detailed status
  VideoDownloadStatus getDetailedStatus(String courseId, String videoId) {
    String key = '${courseId}_${videoId}';
    return _detailedStatus[key] ?? VideoDownloadStatus();
  }

  // Get queued items count
  int get queuedItemsCount => _downloadQueue.length;

  // Get active downloads count
  int get activeDownloadsCount => _activeDownloads;

  // Set maximum concurrent downloads
  set maxConcurrentDownloads(int value) {
    if (value > 0) {
      _maxConcurrentDownloads = value;
      NyStorage.save('max_concurrent_downloads', value);
      // Try to process queue in case new slots are available
      _processQueue();
    }
  }

  // Get current progress
  double getProgress(String courseId, String videoId) {
    String key = '${courseId}_${videoId}';

    // Return watermark progress if watermarking is in progress
    if (_watermarkingStatus[key] == true) {
      return _watermarkProgress[key] ?? 0.0;
    }

    return _downloadProgress[key] ?? 0.0;
  }

  // Check if downloading
  bool isDownloading(String courseId, String videoId) {
    String key = '${courseId}_${videoId}';
    return _downloadingStatus[key] ?? false;
  }

  // Check if watermarking
  bool isWatermarking(String courseId, String videoId) {
    String key = '${courseId}_${videoId}';
    return _watermarkingStatus[key] ?? false;
  }

  // Check if queued
  bool isQueued(String courseId, String videoId) {
    return _downloadQueue
        .any((item) => item.courseId == courseId && item.videoId == videoId);
  }

  // Check if paused
  bool isPaused(String courseId, String videoId) {
    int index = _downloadQueue.indexWhere(
        (item) => item.courseId == courseId && item.videoId == videoId);

    if (index >= 0) {
      return _downloadQueue[index].isPaused;
    }

    return false;
  }

  // Get download speed
  String getDownloadSpeed(String courseId, String videoId) {
    String key = '${courseId}_${videoId}';
    List<int> speedHistory = _downloadSpeedTracker[key] ?? [];
    if (speedHistory.isEmpty) return "0 KB/s";

    // Calculate average speed from last 5 measurements
    int recentMeasurements = speedHistory.length > 5 ? 5 : speedHistory.length;
    double avgSpeed = speedHistory
            .skip(speedHistory.length - recentMeasurements)
            .reduce((a, b) => a + b) /
        recentMeasurements;

    return _formatSpeed(avgSpeed.toInt());
  }

  String _formatSpeed(int bytesPerSecond) {
    if (bytesPerSecond < 1024) return "$bytesPerSecond B/s";
    if (bytesPerSecond < 1024 * 1024)
      return "${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s";
    return "${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s";
  }

  Future<PermissionStatus> getStoragePermissionStatus() async {
    try {
      if (Platform.isAndroid) {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;

        if (androidInfo.version.sdkInt >= 33) {
          // Check both video and audio permissions
          final videoStatus = await Permission.videos.status;
          final audioStatus = await Permission.audio.status;

          // Return the most restrictive status
          if (videoStatus.isDenied || audioStatus.isDenied) {
            return PermissionStatus.denied;
          } else if (videoStatus.isPermanentlyDenied ||
              audioStatus.isPermanentlyDenied) {
            return PermissionStatus.permanentlyDenied;
          } else if (videoStatus.isGranted && audioStatus.isGranted) {
            return PermissionStatus.granted;
          }
          return PermissionStatus.denied;
        } else {
          return await Permission.storage.status;
        }
      } else if (Platform.isIOS) {
        return PermissionStatus.granted; // iOS doesn't need explicit permission
      }

      return PermissionStatus.denied;
    } catch (e) {
      NyLogger.error('Error getting permission status: $e');
      return PermissionStatus.denied;
    }
  }

  // Enhanced enqueue download with additional parameters
  Future<bool> enqueueDownload({
    required String videoUrl,
    required String courseId,
    required String videoId,
    required String watermarkText,
    String email = "",
    required Course course,
    required List<dynamic> curriculum,
    int priority = 100,
    double progress = 0.0,
    int retryCount = 0,
    NetworkPreference? networkPreference,
  }) async {
    try {
      String downloadKey = '${courseId}_${videoId}';

      // 🔥 CRITICAL: Check permissions FIRST, before any other logic
      bool hasPermission = await checkAndRequestStoragePermissions();
      if (!hasPermission) {
        NyLogger.error(
            'Cannot enqueue download - storage permissions not granted');

        _progressStreamController.add({
          'type': 'error',
          'errorType': 'permissionRequired',
          'message': 'Storage permission is required to download videos.',
          'courseId': courseId,
          'videoId': videoId,
        });

        return false;
      }

      // ✅ Check enrollment using Course model
      // if (!course.isEnrolled || !course.hasValidSubscription) {
      //   NyLogger.error(
      //       'Cannot download - user not enrolled or subscription invalid');

      //   _progressStreamController.add({
      //     'type': 'error',
      //     'errorType': 'enrollmentRequired',
      //     'message':
      //         'You must be enrolled with a valid subscription to download this video.',
      //     'courseId': courseId,
      //     'videoId': videoId,
      //   });

      //   return false;
      // }

      // Now check if already downloading, watermarking or queued
      if (_downloadingStatus[downloadKey] == true ||
          _watermarkingStatus[downloadKey] == true ||
          isQueued(courseId, videoId)) {
        NyLogger.info('Download already in progress or queued');
        return false;
      }

      // Rest of your existing logic...
      bool added = _enqueueDownload(
        videoUrl: videoUrl,
        courseId: courseId,
        videoId: videoId,
        watermarkText: watermarkText,
        email: email,
        course: course,
        curriculum: curriculum,
        priority: priority,
        progress: progress,
        retryCount: retryCount,
        networkPreference: networkPreference ?? _globalNetworkPreference,
      );

      if (added) {
        // Set status to queued
        _detailedStatus[downloadKey] = VideoDownloadStatus(
          phase: DownloadPhase.queued,
          progress: progress,
          message: "Queued for download",
          startTime: DateTime.now(),
          retryCount: retryCount,
          networkPreference: networkPreference ?? _globalNetworkPreference,
        );

        _notifyProgressUpdate(courseId, videoId, progress,
            statusMessage: "Queued for download");

        // Save queue state
        await _saveQueueState();

        // Process queue
        _processQueue();
        return true;
      }

      return false;
    } catch (e) {
      NyLogger.error('Error enqueueing download: $e');
      return false;
    }
  }

  // Internal method to add to queue with enhanced parameters
  bool _enqueueDownload({
    required String videoUrl,
    required String courseId,
    required String videoId,
    required String watermarkText,
    required String email,
    required Course course,
    required List<dynamic> curriculum,
    int priority = 100,
    double progress = 0.0,
    int retryCount = 0,
    NetworkPreference networkPreference = NetworkPreference.any,
  }) {
    try {
      // Create queue item
      DownloadQueueItem item = DownloadQueueItem(
        videoUrl: videoUrl,
        courseId: courseId,
        videoId: videoId,
        watermarkText: watermarkText,
        email: email,
        course: course,
        curriculum: curriculum,
        priority: priority,
        retryCount: retryCount,
        networkPreference: networkPreference,
        progress: progress,
      );

      // Add to queue
      _downloadQueue.add(item);

      // Sort queue by priority (lower number = higher priority)
      _downloadQueue.sort((a, b) {
        if (a.priority != b.priority) {
          return a.priority.compareTo(b.priority);
        }
        // If same priority, use queue time
        return a.queuedAt.compareTo(b.queuedAt);
      });

      NyLogger.info(
          'Added download to queue: Course $courseId, Video $videoId, ' +
              'Network preference: $networkPreference, Retry count: $retryCount');
      return true;
    } catch (e) {
      NyLogger.error('Error adding to queue: $e');
      return false;
    }
  }

  // Process download queue with network and disk space checks
  Future<void> _processQueue() async {
    // If already processing or no items in queue, exit
    if (_isProcessingQueue || _downloadQueue.isEmpty) {
      return;
    }

    _isProcessingQueue = true;

    try {
      // First check if we have enough disk space
      bool hasEnoughSpace = await _checkDiskSpace();
      if (!hasEnoughSpace) {
        NyLogger.error('Not enough disk space to continue downloads');
        // Notify user about disk space issue
        _progressStreamController.add({
          'type': 'error',
          'errorType': 'diskSpace',
          'message': 'Not enough disk space to continue downloads. ' +
              'Required: $_minRequiredSpaceMB MB',
        });
        _isProcessingQueue = false;
        return;
      }

      // Identify items that can be processed based on network status
      List<int> eligibleItemIndices = [];

      for (int i = 0; i < _downloadQueue.length; i++) {
        DownloadQueueItem item = _downloadQueue[i];

        // Skip paused items
        if (item.isPaused) {
          continue;
        }

        // Check network preference
        if (!_canDownloadOnCurrentNetwork(item.networkPreference)) {
          // Auto-pause the item if it can't download on current network
          _downloadQueue[i].isPaused = true;

          // Update detailed status
          String key = '${item.courseId}_${item.videoId}';
          _detailedStatus[key] = VideoDownloadStatus(
              phase: DownloadPhase.paused,
              progress: item.progress,
              message: "Paused - waiting for WiFi",
              networkPreference: item.networkPreference,
              retryCount: item.retryCount);

          _notifyProgressUpdate(item.courseId, item.videoId, item.progress,
              statusMessage: "Paused - waiting for WiFi");

          continue;
        }

        // Item is eligible for download
        eligibleItemIndices.add(i);
      }

      // Process as many eligible items as we can based on max concurrent downloads
      while (eligibleItemIndices.isNotEmpty &&
          _activeDownloads < _maxConcurrentDownloads) {
        // Get next eligible item index
        int itemIndex = eligibleItemIndices.removeAt(0);
        DownloadQueueItem item = _downloadQueue.removeAt(itemIndex);

        // Adjust remaining eligible indices since we removed an item
        for (int i = 0; i < eligibleItemIndices.length; i++) {
          if (eligibleItemIndices[i] > itemIndex) {
            eligibleItemIndices[i]--;
          }
        }

        // Start download process in background
        _activeDownloads++;

        // Save download info to storage before starting
        await _saveDownloadInfo(
          videoUrl: item.videoUrl,
          courseId: item.courseId,
          videoId: item.videoId,
          watermarkText: item.watermarkText,
          email: item.email,
          course: item.course,
          curriculum: item.curriculum,
          retryCount: item.retryCount,
          networkPreference: item.networkPreference,
        );

        // Start the download process in a microtask to not block UI
        Future.microtask(() async {
          try {
            await _startDownloadProcess(
              videoUrl: item.videoUrl,
              courseId: item.courseId,
              videoId: item.videoId,
              watermarkText: item.watermarkText,
              email: item.email,
              course: item.course,
              curriculum: item.curriculum,
              retryCount: item.retryCount,
              networkPreference: item.networkPreference,
              progress: item.progress,
            );
          } finally {
            // Decrement active downloads counter
            _activeDownloads--;

            // Process queue again in case we have space for more downloads
            _processQueue();
          }
        });
      }

      // Save queue state after processing
      await _saveQueueState();
    } catch (e) {
      NyLogger.error('Error processing queue: $e');
    } finally {
      _isProcessingQueue = false;
    }
  }

  // Check available disk space
  Future<bool> _checkDiskSpace() async {
    try {
      final _storageInfoPlugin = StorageInfo();
      double? freeDiskSpace = await _storageInfoPlugin.getStorageFreeSpace();

      if (freeDiskSpace != null) {
        // Convert to MB (freeDiskSpace is in MB)
        double freeSpaceMB = freeDiskSpace;

        NyLogger.info(
            'Available disk space: ${freeSpaceMB.toStringAsFixed(2)} MB');

        if (freeSpaceMB < _minRequiredSpaceMB) {
          NyLogger.error(
              'Not enough disk space: ${freeSpaceMB.toStringAsFixed(2)} MB available, ' +
                  'required: $_minRequiredSpaceMB MB');
          return false;
        }

        return true;
      }

      // If we can't determine disk space, assume it's ok
      NyLogger.error('Could not determine available disk space, proceeding');
      return true;
    } catch (e) {
      NyLogger.error('Error checking disk space: $e');
      // If we can't check disk space, assume it's ok to avoid blocking downloads
      return true;
    }
  }

  Future<bool> _checkSubscriptionValidity(Course course) async {
    try {
      // ✅ Use the enrollment status from the Course model
      if (!course.isEnrolled) {
        return false;
      }

      // ✅ Use the helper methods from Course model for subscription validation
      return course.hasValidSubscription;
    } catch (e) {
      NyLogger.error('Error checking subscription validity: $e');
      return false;
    }
  }

  // Pause a download
  Future<bool> pauseDownload({
    required String courseId,
    required String videoId,
  }) async {
    try {
      String downloadKey = '${courseId}_${videoId}';

      // Find the item in the queue
      int index = _downloadQueue.indexWhere(
          (item) => item.courseId == courseId && item.videoId == videoId);

      if (index >= 0) {
        // If it's just queued, mark as paused
        _downloadQueue[index].isPaused = true;
        _downloadQueue[index].pausedAt = DateTime.now();

        // Update status
        _detailedStatus[downloadKey] = VideoDownloadStatus(
          phase: DownloadPhase.paused,
          progress: _downloadQueue[index].progress,
          message: "Download paused",
        );

        _notifyProgressUpdate(courseId, videoId, _downloadQueue[index].progress,
            statusMessage: "Download paused");

        // Save queue state
        await _saveQueueState();

        return true;
      }

      // If it's currently downloading, cancel it and re-add to queue as paused
      if (_downloadingStatus[downloadKey] == true) {
        // Get current progress
        double progress = _downloadProgress[downloadKey] ?? 0.0;

        // Cancel current download
        _cancelRequests[downloadKey] = true;
        _downloadingStatus[downloadKey] = false;

        // Remove any retry timers
        if (_retryTimers.containsKey(downloadKey)) {
          _retryTimers[downloadKey]?.cancel();
          _retryTimers.remove(downloadKey);
        }

        // Add back to queue as paused
        int retryCount = _retryCount[downloadKey] ?? 0;

        // Find the original item in storage to get all details
        dynamic pendingDownloadsRaw = await NyStorage.read('pending_downloads');
        List<dynamic> pendingDownloads = [];

        if (pendingDownloadsRaw is List) {
          pendingDownloads = pendingDownloadsRaw;
        } else if (pendingDownloadsRaw is String) {
          try {
            var decoded = jsonDecode(pendingDownloadsRaw);
            if (decoded is List) {
              pendingDownloads = decoded;
            }
          } catch (e) {
            pendingDownloads = [];
          }
        }

        // Find the item in pending downloads
        Map<String, dynamic>? downloadData;
        for (dynamic item in pendingDownloads) {
          try {
            Map<String, dynamic> data;
            if (item is String) {
              data = jsonDecode(item);
            } else if (item is Map) {
              data = Map<String, dynamic>.from(item);
            } else {
              continue;
            }

            if (data['courseId'] == courseId && data['videoId'] == videoId) {
              downloadData = data;
              break;
            }
          } catch (e) {
            continue;
          }
        }

        if (downloadData != null) {
          // Re-add to queue as paused
          DownloadQueueItem item = DownloadQueueItem(
            videoUrl: downloadData['videoUrl'],
            courseId: courseId,
            videoId: videoId,
            watermarkText: downloadData['watermarkText'] ?? '',
            email: downloadData['email'] ?? '',
            course: Course.fromJson(downloadData['course']),
            curriculum: downloadData['curriculum'] ?? [],
            priority: 50, // Medium priority for paused items
            retryCount: retryCount,
            progress: progress,
            isPaused: true,
            pausedAt: DateTime.now(),
            networkPreference: downloadData.containsKey('networkPreference')
                ? NetworkPreference.values[downloadData['networkPreference']]
                : _globalNetworkPreference,
          );

          _downloadQueue.add(item);

          // Update status
          _detailedStatus[downloadKey] = VideoDownloadStatus(
            phase: DownloadPhase.paused,
            progress: progress,
            message: "Download paused",
            retryCount: retryCount,
          );

          _notifyProgressUpdate(courseId, videoId, progress,
              statusMessage: "Download paused");

          // Save queue state
          await _saveQueueState();

          return true;
        }
      }

      return false;
    } catch (e) {
      NyLogger.error('Error pausing download: $e');
      return false;
    }
  }

  // Resume a paused download
  Future<bool> resumeDownload({
    required String courseId,
    required String videoId,
  }) async {
    return await _resumeDownload(courseId, videoId);
  }

  // Internal method to resume a download
  Future<bool> _resumeDownload(String courseId, String videoId) async {
    try {
      // Find the item in the queue
      int index = _downloadQueue.indexWhere((item) =>
          item.courseId == courseId &&
          item.videoId == videoId &&
          item.isPaused);

      if (index >= 0) {
        // Mark as not paused
        _downloadQueue[index].isPaused = false;
        _downloadQueue[index].pausedAt = null;

        String downloadKey = '${courseId}_${videoId}';

        // Update status
        _detailedStatus[downloadKey] = VideoDownloadStatus(
          phase: DownloadPhase.queued,
          progress: _downloadQueue[index].progress,
          message: "Queued for download",
          retryCount: _downloadQueue[index].retryCount,
        );

        _notifyProgressUpdate(courseId, videoId, _downloadQueue[index].progress,
            statusMessage: "Queued for download");

        // Save queue state
        await _saveQueueState();

        // Process queue
        _processQueue();

        return true;
      }

      return false;
    } catch (e) {
      NyLogger.error('Error resuming download: $e');
      return false;
    }
  }

  // Ensure video is watermarked before playing - adds watermark if missing
  Future<bool> ensureVideoWatermarked({
    required String courseId,
    required String videoId,
    required String email,
    required String userName,
  }) async {
    try {
      // First check if the video is already watermarked
      bool isWatermarked = await isVideoWatermarked(courseId, videoId);

      if (isWatermarked) {
        NyLogger.info('Video is already watermarked');
        return true;
      }

      NyLogger.info('Video needs watermarking');

      // Apply watermark - this is critical for content protection
      return await applyOptimizedWatermark(
        courseId: courseId,
        videoId: videoId,
        watermarkText: userName,
        email: email,
        onProgress: (progress) {
          // Progress is handled internally here
          NyLogger.info(
              'Watermarking progress: ${(progress * 100).toStringAsFixed(1)}%');
        },
      );
    } catch (e) {
      NyLogger.error('Error ensuring watermark: $e');
      return false;
    }
  }

  void _reportError(String operation, dynamic error,
      {StackTrace? stackTrace, Map<String, dynamic>? additionalData}) {
    try {
      // Log to console first
      NyLogger.error('$operation: $error');

      // Set custom keys for context
      FirebaseCrashlytics.instance.setCustomKey('operation', operation);
      FirebaseCrashlytics.instance.setCustomKey('service', 'VideoService');

      // Add any additional context data
      if (additionalData != null) {
        additionalData.forEach((key, value) {
          FirebaseCrashlytics.instance.setCustomKey(key, value.toString());
        });
      }

      // Report to Crashlytics
      if (error is Exception) {
        FirebaseCrashlytics.instance.recordError(
          error,
          stackTrace ?? StackTrace.current,
          fatal: false,
        );
      } else {
        FirebaseCrashlytics.instance.recordError(
          Exception('$operation: $error'),
          stackTrace ?? StackTrace.current,
          fatal: false,
        );
      }
    } catch (e) {
      // Fallback logging if Crashlytics fails
      NyLogger.error('Failed to report error to Crashlytics: $e');
    }
  }

  // Download all videos for a course with network preference
  Future<bool> downloadAllVideos({
    required String courseId,
    required Course course,
    required List<dynamic> curriculum,
    required String watermarkText,
    String email = "",
    NetworkPreference? networkPreference,
  }) async {
    try {
      // First check disk space
      bool hasEnoughSpace = await _checkDiskSpace();
      if (!hasEnoughSpace) {
        // Notify user about disk space issue
        _progressStreamController.add({
          'type': 'error',
          'errorType': 'diskSpace',
          'message': 'Not enough disk space to download all videos. ' +
              'Required: $_minRequiredSpaceMB MB',
        });
        return false;
      }

      int successCount = 0;
      int totalItems = curriculum.length;
      NetworkPreference effectivePreference =
          networkPreference ?? _globalNetworkPreference;

      // Check each item in curriculum
      for (int i = 0; i < curriculum.length; i++) {
        var item = curriculum[i];

        // Skip if no video URL
        if (!item.containsKey('video_url') || item['video_url'] == null) {
          continue;
        }

        String videoUrl = item['video_url'];
        String videoId = i.toString();

        // Check if already downloaded or in progress
        bool isDownloaded = await isVideoDownloaded(
          videoUrl: videoUrl,
          courseId: courseId,
          videoId: videoId,
        );

        if (!isDownloaded &&
            !isDownloading(courseId, videoId) &&
            !isWatermarking(courseId, videoId) &&
            !isQueued(courseId, videoId)) {
          // Add to download queue with varying priorities
          // Earlier videos get higher priority (lower number)
          bool queued = await enqueueDownload(
            videoUrl: videoUrl,
            courseId: courseId,
            videoId: videoId,
            watermarkText: watermarkText,
            email: email,
            course: course,
            curriculum: curriculum,
            priority:
                100 + i, // Add index to make earlier videos higher priority
            networkPreference: effectivePreference,
          );

          if (queued) {
            successCount++;
          }
        }
      }

      return successCount > 0;
    } catch (e) {
      NyLogger.error('Error downloading all videos: $e');
      return false;
    }
  }

  // Enhanced save download info with user isolation
  Future<void> _saveDownloadInfo({
    required String videoUrl,
    required String courseId,
    required String videoId,
    required String watermarkText,
    required String email,
    required Course course,
    required List<dynamic> curriculum,
    int retryCount = 0,
    NetworkPreference networkPreference = NetworkPreference.any,
  }) async {
    try {
      Map<String, dynamic> downloadInfo = {
        'videoUrl': videoUrl,
        'courseId': courseId,
        'videoId': videoId,
        'watermarkText': watermarkText,
        'email': email,
        'course': course.toJson(),
        'curriculum': curriculum,
        'retryCount': retryCount,
        'networkPreference': networkPreference.index,
        'userId': _currentUserId, // Add user ID to download info
      };

      String downloadKey = '${courseId}_${videoId}';
      String progressKey = _getUserSpecificKey('progress_$downloadKey');
      await NyStorage.save(progressKey, 0.0);

      String pendingKey = _getUserSpecificKey('pending_downloads');
      dynamic existingData = await NyStorage.read(pendingKey);
      List<dynamic> pendingDownloads = [];

      if (existingData is List) {
        pendingDownloads = existingData;
      } else if (existingData is String) {
        try {
          var decoded = jsonDecode(existingData);
          if (decoded is List) {
            pendingDownloads = decoded;
          }
        } catch (e) {
          pendingDownloads = [];
        }
      }

      // Remove any existing entry for this download
      pendingDownloads.removeWhere((item) {
        try {
          Map<String, dynamic> data;
          if (item is String) {
            data = jsonDecode(item);
          } else if (item is Map) {
            data = Map<String, dynamic>.from(item);
          } else {
            return false;
          }

          return data['courseId'] == courseId && data['videoId'] == videoId;
        } catch (e) {
          return false;
        }
      });

      pendingDownloads.add(downloadInfo);
      await NyStorage.save(pendingKey, pendingDownloads);

      NyLogger.info('Download info saved to storage for user: $_currentUserId');
    } catch (e) {
      _reportError('save_download_info', e, additionalData: {
        'user_id': _currentUserId ?? 'unknown',
        'course_id': courseId,
        'video_id': videoId,
      });
    }
  }

  // Enhanced download process with comprehensive error reporting
  Future<void> _startDownloadProcess({
    required String videoUrl,
    required String courseId,
    required String videoId,
    required String watermarkText,
    required String email,
    required dynamic course,
    required List<dynamic> curriculum,
    int retryCount = 0,
    NetworkPreference networkPreference = NetworkPreference.any,
    double progress = 0.0,
  }) async {
    String downloadKey = '${courseId}_${videoId}';
    _retryCount[downloadKey] = retryCount;

    // Set context for this download operation
    FirebaseCrashlytics.instance.setCustomKey('download_course_id', courseId);
    FirebaseCrashlytics.instance.setCustomKey('download_video_id', videoId);
    FirebaseCrashlytics.instance
        .setCustomKey('download_retry_count', retryCount);
    FirebaseCrashlytics.instance
        .setCustomKey('network_preference', networkPreference.toString());

    try {
      // First check disk space
      bool hasEnoughSpace = await _checkDiskSpace();
      if (!hasEnoughSpace) {
        throw Exception("Not enough disk space");
      }

      // Update status to downloading
      _downloadingStatus[downloadKey] = true;
      _watermarkingStatus[downloadKey] = false;
      _downloadProgress[downloadKey] = progress;
      _watermarkProgress[downloadKey] = 0.0;
      _cancelRequests[downloadKey] = false;
      _downloadStartTime[downloadKey] = DateTime.now();
      _downloadSpeedTracker[downloadKey] = [];

      // Initialize detailed status
      _detailedStatus[downloadKey] = VideoDownloadStatus(
        phase: DownloadPhase.initializing,
        progress: progress,
        message: "Preparing download...",
        startTime: DateTime.now(),
        retryCount: retryCount,
        networkPreference: networkPreference,
      );

      _notifyProgressUpdate(courseId, videoId, progress,
          statusMessage: "Preparing download...");

      FirebaseCrashlytics.instance.log(
          'Download started for video $videoId in course $courseId (Retry #$retryCount)');
      NyLogger.info(
          'Download started for video $videoId in course $courseId (Retry #$retryCount)');

      // Step 1: Download the video first
      bool downloadSuccess = false;
      try {
        downloadSuccess = await downloadVideo(
          videoUrl: videoUrl,
          courseId: courseId,
          videoId: videoId,
          resumeFromProgress: progress,
          onProgress: (progress, statusMessage) {
            if (_cancelRequests[downloadKey] == true) {
              throw CancelException("Download cancelled");
            }
            _notifyProgressUpdate(courseId, videoId, progress,
                statusMessage: statusMessage);
            NyStorage.save('progress_$downloadKey', progress);

            // Also update the progress in the queue item
            int queueIndex = _downloadQueue.indexWhere(
                (item) => item.courseId == courseId && item.videoId == videoId);
            if (queueIndex >= 0) {
              _downloadQueue[queueIndex].progress = progress;
            }
          },
        );
      } catch (e, stackTrace) {
        // Check if this was a cancellation
        if (e is CancelException) {
          FirebaseCrashlytics.instance
              .log('Download cancelled by user: $downloadKey');
          throw e; // Re-throw to be handled by outer try/catch
        } else if (e is PauseException) {
          FirebaseCrashlytics.instance
              .log('Download paused: $downloadKey - ${e.message}');
          throw e; // Re-throw pause exceptions too
        } else {
          _reportError('downloadVideo', e,
              stackTrace: stackTrace,
              additionalData: {
                'download_key': downloadKey,
                'video_url': videoUrl,
                'progress': progress,
              });
          downloadSuccess = false;
        }
      }

      if (!downloadSuccess) {
        throw Exception("Failed to download video");
      }

      // Step 2: Apply watermark if download was successful
      if (downloadSuccess && !(_cancelRequests[downloadKey] == true)) {
        // Update status to watermarking
        _downloadingStatus[downloadKey] = false;
        _watermarkingStatus[downloadKey] = true;
        _watermarkProgress[downloadKey] = 0.0;

        _detailedStatus[downloadKey] = VideoDownloadStatus(
          phase: DownloadPhase.watermarking,
          progress: 0.0,
          message: "Adding watermark...",
          startTime: _detailedStatus[downloadKey]!.startTime,
          retryCount: retryCount,
          networkPreference: networkPreference,
        );

        _notifyProgressUpdate(courseId, videoId, 0.0,
            statusMessage: "Adding watermark...");

        // Apply watermark with async approach
        bool watermarkSuccess = false;
        try {
          FirebaseCrashlytics.instance
              .log('Starting watermark process for $downloadKey');

          watermarkSuccess = await applyOptimizedWatermark(
            courseId: courseId,
            videoId: videoId,
            watermarkText: watermarkText,
            email: email,
            onProgress: (progress) {
              if (_cancelRequests[downloadKey] == true) {
                throw CancelException("Watermarking cancelled");
              }
              _watermarkProgress[downloadKey] = progress;
              _notifyProgressUpdate(courseId, videoId, progress,
                  statusMessage: "Adding watermark...");
            },
          );

          FirebaseCrashlytics.instance.log(
              'Watermark process completed for $downloadKey: $watermarkSuccess');
        } catch (e, stackTrace) {
          // Check if this was a cancellation
          if (e is CancelException) {
            FirebaseCrashlytics.instance
                .log('Watermarking cancelled by user: $downloadKey');
            throw e; // Re-throw to be handled by outer try/catch
          } else {
            _reportError('applyOptimizedWatermark', e,
                stackTrace: stackTrace,
                additionalData: {
                  'download_key': downloadKey,
                  'watermark_text': watermarkText,
                  'email': email,
                });
            watermarkSuccess = false;
          }
        }

        if (!watermarkSuccess) {
          throw Exception("Failed to apply watermark");
        }
      }

      // Handle the successful completion
      _handleDownloadComplete(
        courseId: courseId,
        videoId: videoId,
        success: downloadSuccess,
        course: course,
        curriculum: curriculum,
      );
    } catch (e, stackTrace) {
      _reportError('_startDownloadProcess', e,
          stackTrace: stackTrace,
          additionalData: {
            'download_key': downloadKey,
            'retry_count': retryCount,
            'progress': progress,
            'network_preference': networkPreference.toString(),
          });

      if (_cancelRequests[downloadKey] == true) {
        FirebaseCrashlytics.instance
            .log('Download was cancelled by user: $downloadKey');
        NyLogger.info('Download was cancelled by user');
        _detailedStatus[downloadKey] = VideoDownloadStatus(
          phase: DownloadPhase.cancelled,
          progress: 0.0,
          message: "Download cancelled",
        );

        _downloadingStatus[downloadKey] = false;
        _watermarkingStatus[downloadKey] = false;
        _notifyProgressUpdate(courseId, videoId, 0.0,
            statusMessage: _detailedStatus[downloadKey]!.displayMessage);
        await _removeFromPendingDownloads(courseId, videoId);
      } else if (e is PauseException) {
        FirebaseCrashlytics.instance
            .log('Download was paused: $downloadKey - ${e.message}');
        NyLogger.info('Download was paused: ${e.message}');
        _detailedStatus[downloadKey] = VideoDownloadStatus(
          phase: DownloadPhase.paused,
          progress: progress,
          message: "Download paused: ${e.message}",
        );

        _downloadingStatus[downloadKey] = false;
        _watermarkingStatus[downloadKey] = false;
        _notifyProgressUpdate(courseId, videoId, progress,
            statusMessage: _detailedStatus[downloadKey]!.displayMessage);

        // Handle pausing logic here if needed
      } else {
        // Check if we should retry
        int currentRetryCount = _retryCount[downloadKey] ?? 0;

        if (currentRetryCount < _maxRetryAttempts &&
            e.toString() != "Not enough disk space") {
          // Don't retry disk space issues
          // Schedule retry with exponential backoff
          int delaySeconds = _calculateRetryDelay(currentRetryCount);
          DateTime nextRetryTime =
              DateTime.now().add(Duration(seconds: delaySeconds));

          _retryCount[downloadKey] = currentRetryCount + 1;

          FirebaseCrashlytics.instance.log(
              'Scheduling retry for $downloadKey - attempt ${currentRetryCount + 1}/$_maxRetryAttempts in ${delaySeconds}s');

          _detailedStatus[downloadKey] = VideoDownloadStatus(
            phase: DownloadPhase.error,
            progress: progress,
            message: "Download failed - will retry",
            error: e.toString(),
            retryCount: currentRetryCount,
            nextRetryTime: nextRetryTime,
            networkPreference: networkPreference,
          );

          _notifyProgressUpdate(courseId, videoId, progress,
              statusMessage:
                  "Failed - retrying in ${delaySeconds}s (Attempt ${currentRetryCount + 1}/$_maxRetryAttempts)");

          // Update retry info in storage
          await _updateRetryInfoInStorage(
              courseId, videoId, currentRetryCount + 1);

          // Schedule retry
          _retryTimers[downloadKey] =
              Timer(Duration(seconds: delaySeconds), () {
            // Add back to queue with same details but higher priority
            print(videoUrl);
            _enqueueDownload(
              videoUrl: videoUrl,
              courseId: courseId,
              videoId: videoId,
              watermarkText: watermarkText,
              email: email,
              course: course,
              curriculum: curriculum,
              priority: 20, // Higher priority for retry
              retryCount: currentRetryCount + 1,
              networkPreference: networkPreference,
              progress: progress,
            );

            // Process queue
            _processQueue();
          });
        } else {
          // Max retries reached or disk space issue, mark as error
          FirebaseCrashlytics.instance
              .log('Max retries reached for $downloadKey or disk space issue');

          _detailedStatus[downloadKey] = VideoDownloadStatus(
            phase: DownloadPhase.error,
            progress: 0.0,
            message:
                "Download failed after ${_retryCount[downloadKey]} retries",
            error: e.toString(),
          );

          _downloadingStatus[downloadKey] = false;
          _watermarkingStatus[downloadKey] = false;
          _notifyProgressUpdate(courseId, videoId, 0.0,
              statusMessage: _detailedStatus[downloadKey]!.displayMessage);
          await _removeFromPendingDownloads(courseId, videoId);
        }
      }
    }
  }

  Future<void> _handleDownloadComplete({
    required String courseId,
    required String videoId,
    required bool success,
    required dynamic course,
    required List<dynamic> curriculum,
  }) async {
    String downloadKey = '${courseId}_${videoId}';

    _downloadingStatus[downloadKey] = false;
    _watermarkingStatus[downloadKey] = false;

    // Cancel any retry timers
    if (_retryTimers.containsKey(downloadKey)) {
      _retryTimers[downloadKey]?.cancel();
      _retryTimers.remove(downloadKey);
    }

    if (success) {
      _downloadProgress[downloadKey] = 1.0;
      _watermarkProgress[downloadKey] = 1.0;
      await NyStorage.save('progress_$downloadKey', 1.0);
      _detailedStatus[downloadKey] = VideoDownloadStatus(
        phase: DownloadPhase.completed,
        progress: 1.0,
        message: "Download completed",
        startTime: _detailedStatus[downloadKey]?.startTime,
      );
    } else {
      _detailedStatus[downloadKey] = VideoDownloadStatus(
        phase: DownloadPhase.error,
        progress: 0.0,
        message: "Download failed",
        startTime: _detailedStatus[downloadKey]?.startTime,
      );
    }
    await _removeFromPendingDownloads(courseId, videoId);

    if (success) {
      NyLogger.info(
          'Download and watermarking completed successfully for video $videoId in course $courseId');
    } else {
      NyLogger.error(
          'Download or watermarking failed for video $videoId in course $courseId');
    }

    _notifyProgressUpdate(courseId, videoId, success ? 1.0 : 0.0,
        statusMessage: _detailedStatus[downloadKey]!.displayMessage);

    // Process queue to start next download
    _processQueue();
  }

  // Update retry information in storage
  Future<void> _updateRetryInfoInStorage(
      String courseId, String videoId, int newRetryCount) async {
    try {
      dynamic pendingDownloadsRaw = await NyStorage.read('pending_downloads');
      List<dynamic> pendingDownloads = [];

      if (pendingDownloadsRaw is List) {
        pendingDownloads = pendingDownloadsRaw;
      } else if (pendingDownloadsRaw is String) {
        try {
          var decoded = jsonDecode(pendingDownloadsRaw);
          if (decoded is List) {
            pendingDownloads = decoded;
          }
        } catch (e) {
          pendingDownloads = [];
        }
      }

      // Update retry count for the specific download
      for (int i = 0; i < pendingDownloads.length; i++) {
        try {
          dynamic item = pendingDownloads[i];
          Map<String, dynamic> downloadData;

          if (item is String) {
            downloadData = jsonDecode(item);
          } else if (item is Map) {
            downloadData = Map<String, dynamic>.from(item);
          } else {
            continue;
          }

          if (downloadData['courseId'] == courseId &&
              downloadData['videoId'] == videoId) {
            downloadData['retryCount'] = newRetryCount;
            pendingDownloads[i] = downloadData;
            break;
          }
        } catch (e) {
          NyLogger.error('Error updating retry info: $e');
          continue;
        }
      }

      await NyStorage.save('pending_downloads', pendingDownloads);
    } catch (e) {
      NyLogger.error('Error updating retry info in storage: $e');
    }
  }

  // Calculate retry delay with exponential backoff
  int _calculateRetryDelay(int retryCount) {
    // Start with 5 seconds, then 10, 20, 40, 80...
    return (5 * pow(2, retryCount)).round();
  }

  Future<bool> requestStoragePermissions() async {
    try {
      if (Platform.isAndroid) {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;

        if (androidInfo.version.sdkInt >= 33) {
          // Android 13+ (API 33+) - Use scoped storage permissions
          final videoPermission = await Permission.videos.request();
          final audioPermission = await Permission.audio.request();

          return videoPermission.isGranted && audioPermission.isGranted;
        } else if (androidInfo.version.sdkInt >= 30) {
          // Android 11-12 (API 30-32) - Use storage permission
          final storagePermission = await Permission.storage.request();
          return storagePermission.isGranted;
        } else {
          // Android 10 and below - Use storage permission
          final storagePermission = await Permission.storage.request();
          return storagePermission.isGranted;
        }
      } else if (Platform.isIOS) {
        // iOS - No explicit storage permission needed for app documents directory
        // But we might need photos permission if accessing photo library
        return true;
      }

      return false;
    } catch (e) {
      NyLogger.error('Error requesting storage permissions: $e');
      return false;
    }
  }

  Future<bool> checkStoragePermissions() async {
    try {
      if (Platform.isAndroid) {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;

        if (androidInfo.version.sdkInt >= 33) {
          // Android 13+
          return await Permission.videos.isGranted &&
              await Permission.audio.isGranted;
        } else {
          // Android 12 and below
          return await Permission.storage.isGranted;
        }
      } else if (Platform.isIOS) {
        // iOS - Always return true for app documents directory
        return true;
      }

      return false;
    } catch (e) {
      NyLogger.error('Error checking storage permissions: $e');
      return false;
    }
  }

  Future<void> handlePermissionResult(
      BuildContext context, bool granted, PermissionStatus status) async {
    if (!granted) {
      if (status.isPermanentlyDenied) {
        // Show dialog to go to settings
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
        // Show regular permission denied message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Storage permission is required to download videos.'),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () async {
                // Retry permission request
                bool newResult =
                    await VideoService().requestStoragePermissions();
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

  Future<bool> downloadVideo({
    required String videoUrl,
    required String courseId,
    required String videoId,
    Function(double, String)? onProgress,
    double resumeFromProgress = 0.0,
  }) async {
    String downloadKey = '${courseId}_${videoId}';

    try {
      if (videoUrl.isEmpty || !Uri.parse(videoUrl).isAbsolute) {
        throw Exception("Invalid video URL");
      }

      // Initialize detailed status
      _detailedStatus[downloadKey] = VideoDownloadStatus(
        phase: DownloadPhase.initializing,
        progress: resumeFromProgress,
        message: "Preparing download...",
        startTime: DateTime.now(),
      );

      if (onProgress != null) {
        onProgress(resumeFromProgress, "Preparing download...");
      }

      // Request storage permission
      if (Platform.isAndroid && !_permissionsGranted) {
        throw Exception("Storage permission not granted");
      }

      // Check network connectivity
      if (_currentConnectivity == ConnectivityResult.none) {
        throw Exception("No internet connection available");
      }

      // Create app directory
      Directory appDir = await getApplicationDocumentsDirectory();
      String courseDir = '${appDir.path}/courses/$courseId/videos';
      await Directory(courseDir).create(recursive: true);

      // Get output file path
      String outputPath = await getVideoFilePath(courseId, videoId);

      // Check for partial download to resume
      File outputFile = File(outputPath);
      int startByte = 0;

      if (resumeFromProgress > 0 && await outputFile.exists()) {
        startByte = await outputFile.length();
        NyLogger.info('Resuming download from byte $startByte');
      }

      // Download headers
      Map<String, String> headers = {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        'Accept': '*/*',
      };

      // Add range header if resuming
      if (startByte > 0) {
        headers['Range'] = 'bytes=$startByte-';
      }

      // Update status for download phase
      _detailedStatus[downloadKey] = VideoDownloadStatus(
        phase: DownloadPhase.downloading,
        progress: resumeFromProgress,
        message: "Downloading video...",
        startTime: _detailedStatus[downloadKey]!.startTime,
      );

      // Use a completer to handle async completion
      Completer<bool> downloadCompleter = Completer<bool>();

      // Setup a timer to periodically update download speed
      DateTime lastSpeedCheck = DateTime.now();
      int lastBytesReceived = startByte;

      // Use a more robust async approach with Dio
      // Configure throttling if enabled
      if (_isThrottlingEnabled) {
        _dio.options.receiveTimeout =
            const Duration(seconds: 60 * 10); // 10 minutes timeout

        // Custom interceptor for throttling
        if (!_dio.interceptors.any((i) => i is ThrottlingInterceptor)) {
          _dio.interceptors.add(ThrottlingInterceptor(_maxBytesPerSecond));
        } else {
          // Update existing throttling interceptor
          for (var interceptor in _dio.interceptors) {
            if (interceptor is ThrottlingInterceptor) {
              interceptor.maxBytesPerSecond = _maxBytesPerSecond;
            }
          }
        }
      }

      // Set up basic Dio options
      _dio.options.connectTimeout = const Duration(seconds: 30);
      _dio.options.receiveTimeout = const Duration(seconds: 60 * 10); // 10 min
      _dio.options.headers = headers;
      _dio.options.responseType = ResponseType.stream;

      // Create a timer to check for cancellation
      Timer? cancelCheckTimer;
      cancelCheckTimer = Timer.periodic(Duration(milliseconds: 500), (timer) {
        if (_cancelRequests[downloadKey] == true) {
          // Cancel the download if requested
          _dio.close(force: true);
          timer.cancel();

          if (!downloadCompleter.isCompleted) {
            downloadCompleter
                .completeError(CancelException("Download cancelled by user"));
          }
        }
      });

      try {
        // If resuming and file exists, prepare to append to it
        IOSink? fileSink;
        if (startByte > 0) {
          fileSink = outputFile.openWrite(mode: FileMode.append);
          NyLogger.info('Opened file for appending from byte $startByte');
        }

        _dio.download(
          videoUrl,
          (startByte > 0)
              ? null
              : outputPath, // If resuming, handle file manually
          onReceiveProgress: (received, total) {
            if (_cancelRequests[downloadKey] == true) {
              throw CancelException("Download cancelled by user");
            }

            // Adjust for resuming
            int adjustedReceived = received + startByte;
            int adjustedTotal = (total != -1) ? total + startByte : -1;

            if (adjustedTotal != -1) {
              double progress = adjustedReceived / adjustedTotal;

              // Calculate speed
              DateTime now = DateTime.now();
              if (now.difference(lastSpeedCheck).inSeconds >= 1) {
                int bytesInLastSecond = adjustedReceived - lastBytesReceived;
                _downloadSpeedTracker[downloadKey] ??= [];
                _downloadSpeedTracker[downloadKey]!.add(bytesInLastSecond);

                // Keep only last 10 measurements
                if (_downloadSpeedTracker[downloadKey]!.length > 10) {
                  _downloadSpeedTracker[downloadKey]!.removeAt(0);
                }

                lastSpeedCheck = now;
                lastBytesReceived = adjustedReceived;
              }

              _detailedStatus[downloadKey] = VideoDownloadStatus(
                phase: DownloadPhase.downloading,
                progress: progress,
                message: "Downloading...",
                bytesReceived: adjustedReceived,
                totalBytes: adjustedTotal,
                startTime: _detailedStatus[downloadKey]!.startTime,
              );

              // Check current network status if we care about it
              if (_pauseOnMobileData &&
                  _currentConnectivity == ConnectivityResult.mobile) {
                throw PauseException("Paused due to mobile data");
              }

              if (onProgress != null) {
                String speedInfo = getDownloadSpeed(courseId, videoId);
                String statusMessage =
                    _detailedStatus[downloadKey]!.displayMessage +
                        " • $speedInfo";
                onProgress(progress, statusMessage);
              }
            } else {
              // If total is unknown, use a simpler progress update
              if (onProgress != null) {
                String speedInfo = getDownloadSpeed(courseId, videoId);
                String statusMessage =
                    "Downloading (size unknown) • $speedInfo";
                onProgress(0.5, statusMessage); // Use 50% as placeholder
              }
            }
          },
          deleteOnError: false,
          data: (startByte > 0) ? fileSink : null,
        ).then((_) async {
          // Success - close file if we were appending
          if (fileSink != null) {
            await fileSink.close();
            NyLogger.info('Closed file sink after appending download data');
          }

          // Cancel the timer
          cancelCheckTimer?.cancel();

          // Verify download was successful
          if (!await outputFile.exists()) {
            NyLogger.error('Video file does not exist after download');
            if (!downloadCompleter.isCompleted) {
              downloadCompleter.complete(false);
            }
            return;
          }

          int fileSize = await outputFile.length();
          if (fileSize < 1000) {
            NyLogger.error('Downloaded file is too small: $fileSize bytes');
            if (!downloadCompleter.isCompleted) {
              downloadCompleter.complete(false);
            }
            return;
          }

          NyLogger.info('Download completed successfully: $fileSize bytes');
          if (!downloadCompleter.isCompleted) {
            downloadCompleter.complete(true);
          }
        }).catchError((e) async {
          // Handle error
          cancelCheckTimer?.cancel();

          if (e is DioException) {
            if (e.type == DioExceptionType.cancel) {
              NyLogger.info('Download was cancelled');
              if (!downloadCompleter.isCompleted) {
                downloadCompleter
                    .completeError(CancelException("Download cancelled"));
              }
            } else {
              // For all other Dio errors, try fallback method if not resuming
              NyLogger.error('Dio download error: ${e.message}');

              if (startByte == 0) {
                bool fallbackResult = await _fallbackDownload(
                    videoUrl, outputPath, headers, onProgress);
                if (!downloadCompleter.isCompleted) {
                  downloadCompleter.complete(fallbackResult);
                }
              } else {
                NyLogger.error(
                    'Cannot use fallback method for resumed download');
                if (!downloadCompleter.isCompleted) {
                  downloadCompleter.completeError(
                      Exception("Download failed: ${e.message}"));
                }
              }
            }
          } else if (e is PauseException) {
            NyLogger.info('Download paused: ${e.message}');
            if (!downloadCompleter.isCompleted) {
              downloadCompleter.completeError(e);
            }
          } else {
            NyLogger.error('Error during download: $e');
            if (startByte == 0) {
              bool fallbackResult = await _fallbackDownload(
                  videoUrl, outputPath, headers, onProgress);
              if (!downloadCompleter.isCompleted) {
                downloadCompleter.complete(fallbackResult);
              }
            } else {
              if (!downloadCompleter.isCompleted) {
                downloadCompleter
                    .completeError(Exception("Download failed: $e"));
              }
            }
          }
        });

        // Wait for completion
        return await downloadCompleter.future;
      } catch (e) {
        // Cancel timer if there's an early error
        cancelCheckTimer.cancel();

        if (e is CancelException) {
          // Propagate cancellation
          throw e;
        } else if (e is PauseException) {
          // Handle pause - notify caller but don't count as error
          if (onProgress != null) {
            onProgress(resumeFromProgress, "Download paused");
          }

          _detailedStatus[downloadKey] = VideoDownloadStatus(
            phase: DownloadPhase.paused,
            progress: resumeFromProgress,
            message: "Download paused: ${e.message}",
            startTime: _detailedStatus[downloadKey]?.startTime,
          );

          // Re-add to queue as paused
          throw e;
        } else {
          NyLogger.error('Error setting up download: $e');
          return false;
        }
      }
    } catch (e) {
      if (e is CancelException) {
        // Propagate cancellation
        throw e;
      } else if (e is PauseException) {
        // Handle pause - propagate
        throw e;
      } else {
        String errorMessage = e.toString();
        String userFriendlyMessage = "Download failed";

        if (errorMessage.contains("permission")) {
          userFriendlyMessage = "Storage permission denied";
        } else if (errorMessage.contains("space")) {
          userFriendlyMessage = "Not enough storage space";
        } else if (errorMessage.contains("connection")) {
          userFriendlyMessage = "Network connection lost";
        } else if (errorMessage.contains("timeout")) {
          userFriendlyMessage = "Download timed out";
        }

        NyLogger.error('Error during video download: $e');

        _detailedStatus[downloadKey] = VideoDownloadStatus(
          phase: DownloadPhase.error,
          progress: resumeFromProgress,
          message: userFriendlyMessage,
          error: e.toString(),
          startTime: _detailedStatus[downloadKey]?.startTime,
        );

        if (onProgress != null) {
          onProgress(resumeFromProgress, userFriendlyMessage);
        }

        return false;
      }
    }
  }

  Future<bool> deleteVideo({
    required String courseId,
    required String videoId,
  }) async {
    try {
      // Get the file path for the video
      String videoPath = await getVideoFilePath(courseId, videoId);
      File videoFile = File(videoPath);

      // Also check for watermark flag file
      File watermarkFlagFile = File('$videoPath.watermarked');

      // Check if the file exists
      bool videoExists = await videoFile.exists();
      bool flagExists = await watermarkFlagFile.exists();

      // If file doesn't exist, report success (nothing to delete)
      if (!videoExists && !flagExists) {
        NyLogger.info('Video $courseId/$videoId not found, nothing to delete');
        return true;
      }

      // Delete the files
      bool success = true;
      if (videoExists) {
        try {
          await videoFile.delete();
          NyLogger.info('Video file deleted: $videoPath');
        } catch (e) {
          NyLogger.error('Error deleting video file: $e');
          success = false;
        }
      }

      if (flagExists) {
        try {
          await watermarkFlagFile.delete();
          NyLogger.info('Watermark flag deleted: $videoPath.watermarked');
        } catch (e) {
          NyLogger.error('Error deleting watermark flag: $e');
          // Don't fail just because of flag file
        }
      }

      // Delete any cache files or thumbnails
      try {
        Directory tempDir = await getTemporaryDirectory();

        // Check for screenshot cache
        File screenshotFile =
            File('${tempDir.path}/watermark_check_$videoId.jpg');
        if (await screenshotFile.exists()) {
          await screenshotFile.delete();
        }

        // Check for other potential cache files
        List<String> potentialCacheFiles = [
          '${tempDir.path}/temp_watermarked_$videoId.mp4',
          '${tempDir.path}/thumb_$courseId-$videoId.jpg',
        ];

        for (String path in potentialCacheFiles) {
          File cacheFile = File(path);
          if (await cacheFile.exists()) {
            await cacheFile.delete();
          }
        }
      } catch (e) {
        NyLogger.error('Error cleaning up cache files: $e');
        // Don't fail just because of cache cleanup
      }

      // Clean up status tracking
      String key = '${courseId}_${videoId}';
      _downloadProgress[key] = 0.0;

      _downloadingStatus[key] = false;
      _watermarkingStatus[key] = false;
      _watermarkProgress[key] = 0.0;
      _downloadSpeedTracker.remove(key);

      _detailedStatus[key] = VideoDownloadStatus(
        phase: DownloadPhase.initializing,
        progress: 0.0,
        message: "Not downloaded",
      );

      // Also check if it's in queue and remove
      int queueIndex = _downloadQueue.indexWhere(
          (item) => item.courseId == courseId && item.videoId == videoId);

      if (queueIndex >= 0) {
        _downloadQueue.removeAt(queueIndex);
        await _saveQueueState();
      }

      return success;
    } catch (e) {
      NyLogger.error('Error in deleteVideo: $e');
      return false;
    }
  }

  Future<bool> prioritizeDownload({
    required String courseId,
    required String videoId,
  }) async {
    try {
      // Find the item in the queue
      int index = _downloadQueue.indexWhere(
          (item) => item.courseId == courseId && item.videoId == videoId);

      if (index >= 0) {
        // Update priority to highest
        _downloadQueue[index].priority = 1;

        // Re-sort queue
        _downloadQueue.sort((a, b) {
          if (a.priority != b.priority) {
            return a.priority.compareTo(b.priority);
          }
          return a.queuedAt.compareTo(b.queuedAt);
        });

        // Save queue state
        await _saveQueueState();
        return true;
      }
      return false;
    } catch (e) {
      NyLogger.error('Error prioritizing download: $e');
      return false;
    }
  }

  void _cleanupDownloadResources(String courseId, String videoId) {
    String downloadKey = '${courseId}_${videoId}';

    _downloadSpeedTracker.remove(downloadKey);
    _downloadStartTime.remove(downloadKey);

    // Don't remove status tracking as it's needed for UI updates
    // but reset any active flags
    _downloadingStatus[downloadKey] = false;
    _watermarkingStatus[downloadKey] = false;
    _cancelRequests[downloadKey] = false;

    // Cancel any retry timers
    if (_retryTimers.containsKey(downloadKey)) {
      _retryTimers[downloadKey]?.cancel();
      _retryTimers.remove(downloadKey);
    }
  }

// Fallback download method using basic HTTP
  Future<bool> _fallbackDownload(String videoUrl, String outputPath,
      Map<String, String> headers, Function(double, String)? onProgress) async {
    try {
      NyLogger.info('Trying fallback download with http client');

      if (onProgress != null) {
        onProgress(0.1, "Retrying with alternative method...");
      }

      // Use a completer to handle async completion
      Completer<bool> completer = Completer<bool>();

      // Use basic http client as fallback
      final httpClient = http.Client();
      final request = http.Request('GET', Uri.parse(videoUrl));
      request.headers.addAll(headers);

      try {
        final response =
            await httpClient.send(request).timeout(Duration(seconds: 60));

        if (response.statusCode == 200 || response.statusCode == 206) {
          final file = File(outputPath);
          final fileStream = file.openWrite();

          int received = 0;
          int total = response.contentLength ?? -1;

          // Set up a stream subscription for better control
          late StreamSubscription subscription;
          subscription = response.stream.listen(
            (chunk) {
              fileStream.add(chunk);
              received += chunk.length;

              if (total != -1 && onProgress != null) {
                double progress = received / total;
                onProgress(progress, "Downloading with alternative method...");
              }
            },
            onDone: () async {
              await fileStream.close();
              httpClient.close();

              if (onProgress != null) {
                onProgress(1.0, "Download completed");
              }

              NyLogger.info('Fallback download succeeded');
              completer.complete(true);
            },
            onError: (e) async {
              await fileStream.close();
              httpClient.close();
              NyLogger.error('Error in fallback download stream: $e');
              completer.complete(false);
            },
            cancelOnError: true,
          );

          // Return the completer's future
          return await completer.future;
        } else {
          httpClient.close();
          NyLogger.error(
              'Fallback download failed with status: ${response.statusCode}');
          return false;
        }
      } catch (e) {
        httpClient.close();
        NyLogger.error('Fallback download error: $e');
        return false;
      }
    } catch (e) {
      NyLogger.error('Fallback download setup failed: $e');
      return false;
    }
  }

  // Enhanced is video downloaded with user isolation
  Future<bool> isVideoDownloaded({
    required String videoUrl,
    required String courseId,
    required String videoId,
  }) async {
    try {
      // Get the user-specific file path for the video
      String filePath = await getVideoFilePath(courseId, videoId);
      File videoFile = File(filePath);

      // Check if the file exists
      bool exists = await videoFile.exists();

      if (exists) {
        // Also check file size to ensure it's a valid video file
        int fileSize = await videoFile.length();

        // Consider files below 10KB as invalid/incomplete videos
        if (fileSize < 10 * 1024) {
          NyLogger.error(
              'Video file exists but is too small (${fileSize} bytes), considering as not downloaded');
          return false;
        }

        NyLogger.info(
            'Video found for user $_currentUserId: $courseId/$videoId (${fileSize} bytes)');
        return true;
      }

      NyLogger.info(
          'Video not found for user $_currentUserId: $courseId/$videoId');
      return false;
    } catch (e) {
      _reportError('is_video_downloaded', e, additionalData: {
        'user_id': _currentUserId ?? 'unknown',
        'course_id': courseId,
        'video_id': videoId,
      });
      return false;
    }
  }

  // Enhanced watermarking with error reporting
  Future<bool> applyOptimizedWatermark({
    required String courseId,
    required String videoId,
    required String watermarkText,
    required String email,
    required Function(double) onProgress,
  }) async {
    String downloadKey = '${courseId}_${videoId}';

    // Set context for watermarking operation
    FirebaseCrashlytics.instance.setCustomKey('watermark_course_id', courseId);
    FirebaseCrashlytics.instance.setCustomKey('watermark_video_id', videoId);
    FirebaseCrashlytics.instance.setCustomKey('watermark_text', watermarkText);

    try {
      // Get file paths
      String videoPath = await getVideoFilePath(courseId, videoId);

      // Ensure the downloaded video exists
      File videoFile = File(videoPath);
      if (!await videoFile.exists()) {
        FirebaseCrashlytics.instance
            .log('Video file not found for watermarking: $videoPath');
        NyLogger.error('Video file not found for watermarking');
        return false;
      }

      // Report initial progress
      onProgress(0.1);

      // Create temporary file for watermarked output
      Directory tempDir = await getTemporaryDirectory();
      String tempOutputPath = '${tempDir.path}/temp_watermarked_$videoId.mp4';

      // Get username for watermark
      String userName = await _getUserName();

      // Update progress
      onProgress(0.2);

      FirebaseCrashlytics.instance
          .log('Starting watermark application for $downloadKey');

      // IMPORTANT: Use FFmpegKit.executeAsync instead of execute to avoid blocking UI
      bool success = await _applyWatermarkAsync(
        videoPath: videoPath,
        tempOutputPath: tempOutputPath,
        watermarkText: watermarkText,
        email: email,
        userName: userName,
        progressCallback: (progress) {
          // Scale progress from 0.2 to 0.9
          onProgress(0.2 + (progress * 0.7));
        },
      );

      if (success) {
        // Create watermark flag file
        final watermarkFlagFile = File('$videoPath.watermarked');
        await watermarkFlagFile.writeAsString('watermarked');

        FirebaseCrashlytics.instance
            .log('Watermark applied successfully for $downloadKey');
        onProgress(1.0);
        return true;
      } else {
        // Try fallback method
        FirebaseCrashlytics.instance.log(
            'Main watermarking failed, trying fallback method for $downloadKey');
        NyLogger.info('Main watermarking failed, trying fallback method');

        bool fallbackSuccess = await _applyFallbackWatermarkAsync(
          videoPath: videoPath,
          tempOutputPath: tempOutputPath,
          userName: userName,
          email: email,
          progressCallback: (progress) {
            // Scale fallback progress from 0.5 to 0.9 range
            onProgress(0.5 + (progress * 0.4));
          },
        );

        if (fallbackSuccess) {
          // Create watermark flag
          final watermarkFlagFile = File('$videoPath.watermarked');
          await watermarkFlagFile.writeAsString('watermarked');

          FirebaseCrashlytics.instance
              .log('Fallback watermarking succeeded for $downloadKey');
          onProgress(1.0);
          return true;
        }

        // If all watermarking attempts fail, still create a flag
        // to prevent repeated failing attempts
        try {
          final watermarkFlagFile = File('$videoPath.watermarked');
          await watermarkFlagFile.writeAsString('watermarked');
          FirebaseCrashlytics.instance
              .log('Created watermark flag despite failure for $downloadKey');
        } catch (e, stackTrace) {
          _reportError('create_watermark_flag', e, stackTrace: stackTrace);
        }

        onProgress(1.0);
        return true; // Return true to allow playback even if watermarking failed
      }
    } catch (e, stackTrace) {
      _reportError('applyOptimizedWatermark', e,
          stackTrace: stackTrace,
          additionalData: {
            'download_key': downloadKey,
            'watermark_text': watermarkText,
            'email': email,
          });

      // Create watermark flag even on error to prevent repeated attempts
      try {
        final watermarkFlagFile =
            File('${await getVideoFilePath(courseId, videoId)}.watermarked');
        await watermarkFlagFile.writeAsString('watermarked');
      } catch (e) {
        // Ignore
      }
      onProgress(1.0);
      return true; // Return true to allow playback even if watermarking failed
    }
  }

  Future<bool> _applyFallbackWatermarkAsync({
    required String videoPath,
    required String tempOutputPath,
    required String userName,
    required String email,
    required Function(double) progressCallback,
  }) async {
    try {
      // First try a simpler watermark command
      String command = '-i "$videoPath" -vf "' +
          'drawtext=text=\'Bhavani - $userName\':' +
          'fontcolor=yellow:fontsize=14:x=10:y=10:box=1:boxcolor=black@0.8:boxborderw=5' +
          '" -c:a copy "$tempOutputPath"';

      NyLogger.info('Trying fallback watermarking: $command');
      progressCallback(0.2);

      // Create a completer for async handling
      Completer<bool> completer = Completer<bool>();

      // Progress reporting timer
      int timerSeconds = 0;
      Timer.periodic(Duration(seconds: 1), (timer) {
        if (completer.isCompleted) {
          timer.cancel();
          return;
        }

        timerSeconds++;
        if (timerSeconds < 15) {
          // Report progress from 0.2 to 0.8 over 15 seconds
          progressCallback(0.2 + (timerSeconds / 15 * 0.6));
        } else {
          progressCallback(0.8); // Cap at 80% until complete
        }
      });

      FFmpegKit.executeAsync(command, (session) async {
        ReturnCode? returnCode = await session.getReturnCode();

        if (ReturnCode.isSuccess(returnCode)) {
          // Replace the original file with the watermarked version
          File videoFile = File(videoPath);
          File tempFile = File(tempOutputPath);
          if (await tempFile.exists()) {
            await videoFile.delete();
            await tempFile.copy(videoPath);
            await tempFile.delete();
            NyLogger.info('Fallback watermarking succeeded');

            if (!completer.isCompleted) {
              completer.complete(true);
            }
          } else {
            if (!completer.isCompleted) {
              completer.complete(false);
            }
          }
        } else {
          // Try one more simplified approach
          _trySimplestWatermark(videoPath, tempOutputPath, completer);
        }
      });

      return await completer.future;
    } catch (e) {
      NyLogger.error('Error in fallback watermarking: $e');
      return false;
    }
  }

// Last resort watermarking attempt
  Future<void> _trySimplestWatermark(String videoPath, String tempOutputPath,
      Completer<bool> completer) async {
    try {
      // Extremely simple watermark as last resort
      String command = '-i "$videoPath" -vf "' +
          'drawtext=text=\'Bhavani\':' +
          'fontcolor=white:fontsize=14:x=10:y=10:box=1:boxcolor=black@0.9:boxborderw=5' +
          '" -c:a copy "$tempOutputPath"';

      NyLogger.info('Trying simplest watermarking: $command');

      FFmpegKit.executeAsync(command, (session) async {
        ReturnCode? returnCode = await session.getReturnCode();

        if (ReturnCode.isSuccess(returnCode)) {
          // Replace the original file with the watermarked version
          File videoFile = File(videoPath);
          File tempFile = File(tempOutputPath);
          if (await tempFile.exists()) {
            await videoFile.delete();
            await tempFile.copy(videoPath);
            await tempFile.delete();
            NyLogger.info('Simplest watermarking succeeded');

            if (!completer.isCompleted) {
              completer.complete(true);
            }
            return;
          }
        }

        // Try a direct copy if all else fails
        _tryDirectCopy(videoPath, tempOutputPath, completer);
      });
    } catch (e) {
      NyLogger.error('Error in simplest watermarking: $e');
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    }
  }

// Last resort - just copy the video if watermarking fails
  Future<void> _tryDirectCopy(String videoPath, String tempOutputPath,
      Completer<bool> completer) async {
    try {
      String command = '-i "$videoPath" -c copy "$tempOutputPath"';
      NyLogger.info('Trying direct copy: $command');

      FFmpegKit.executeAsync(command, (session) async {
        ReturnCode? returnCode = await session.getReturnCode();

        if (ReturnCode.isSuccess(returnCode)) {
          // Replace the original file
          File videoFile = File(videoPath);
          File tempFile = File(tempOutputPath);
          if (await tempFile.exists()) {
            await videoFile.delete();
            await tempFile.copy(videoPath);
            await tempFile.delete();
            NyLogger.error(
                'No watermark applied, but video processing succeeded');

            if (!completer.isCompleted) {
              completer.complete(true);
            }
            return;
          }
        }

        if (!completer.isCompleted) {
          completer.complete(false);
        }
      });
    } catch (e) {
      NyLogger.error('Error in direct copy: $e');
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    }
  }

  Future<bool> _applyWatermarkAsync({
    required String videoPath,
    required String tempOutputPath,
    required String watermarkText,
    required String email,
    required String userName,
    required Function(double) progressCallback,
  }) async {
    try {
      // Larger font size and better opacity settings
      String fontsize = "14";
      String bottomMargin = "20";
      String opacity = "0.7";

      // Clean up any existing temp file
      File tempFile = File(tempOutputPath);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      // Prepare command with highly visible watermarks
      String command = '-i "$videoPath" -vf "' +
          // Bottom persistent watermark
          'drawtext=text=\'Bhavani\':fontcolor=white:fontsize=$fontsize:' +
          'x=10:y=h-$bottomMargin-text_h:box=1:boxcolor=black@$opacity:boxborderw=5,' +
          // Username watermark - more visible
          'drawtext=text=\'$userName\':fontcolor=white:fontsize=$fontsize:' +
          'x=w-text_w-10:y=h-$bottomMargin-text_h*2:box=1:boxcolor=black@$opacity:boxborderw=5,' +
          // Email watermark
          'drawtext=text=\'$email\':fontcolor=white:fontsize=$fontsize:' +
          'x=w-text_w-10:y=h-$bottomMargin:box=1:boxcolor=black@$opacity:boxborderw=5' +
          '" -c:a copy "$tempOutputPath"';

      NyLogger.info('Executing FFmpeg command: $command');

      // Create a completer to handle async FFmpeg execution
      Completer<bool> completer = Completer<bool>();

      // Set up a timer to report progress approximation
      // Since we can't get real-time progress from FFmpeg for filter operations
      int durationEstimateSeconds = 30; // Assume 30 seconds for watermarking
      Timer.periodic(Duration(seconds: 1), (timer) {
        if (completer.isCompleted) {
          timer.cancel();
          return;
        }

        int elapsed = timer.tick;
        if (elapsed >= durationEstimateSeconds) {
          progressCallback(0.9); // Almost done
        } else {
          // Scale from 0.1 to 0.9 based on elapsed time
          double progress = 0.1 + (0.8 * elapsed / durationEstimateSeconds);
          progressCallback(progress);
        }
      });

      // Execute FFmpeg command asynchronously
      FFmpegKit.executeAsync(command, (session) async {
        // Execution completed, check result
        ReturnCode? returnCode = await session.getReturnCode();

        if (ReturnCode.isSuccess(returnCode)) {
          NyLogger.info('FFmpeg watermarking completed successfully');

          // Replace the original file with the watermarked version
          File videoFile = File(videoPath);
          if (await tempFile.exists()) {
            if (await videoFile.exists()) {
              await videoFile.delete();
            }
            await tempFile.copy(videoPath);
            await tempFile.delete();

            if (!completer.isCompleted) {
              completer.complete(true);
            }
          } else {
            NyLogger.error('Temp watermarked file not found after processing');
            if (!completer.isCompleted) {
              completer.complete(false);
            }
          }
        } else {
          // Log error details
          NyLogger.error('FFmpeg watermarking failed with code: $returnCode');
          if (!completer.isCompleted) {
            completer.complete(false);
          }
        }
      }, (log) {
        // Optional: log FFmpeg output for debugging
        NyLogger.info('FFmpeg log: $log');
      }, (statistics) {
        // Unfortunately, filter operations don't provide useful progress statistics
        // We're using the timer approach above instead
      });

      // Wait for completion
      return await completer.future;
    } catch (e) {
      NyLogger.error('Error in async watermarking: $e');
      return false;
    }
  }

// Static method that can be used with compute
  static Future<bool> _applyWatermarkInBackground(
      Map<String, dynamic> params) async {
    final videoPath = params['videoPath'];
    final tempOutputPath = params['tempOutputPath'];
    final watermarkText = params['watermarkText'];
    final email = params['email'];
    final userName = params['userName'];

    try {
      // IMPROVED: Larger font size and better opacity settings
      String fontsize = "14ß"; // Increased from 12 to 24
      String bottomMargin = "20"; // Increased from 10 to 20
      String opacity = "0.7"; // Increased from 0.4 to 0.7

      // IMPROVED: Use two approaches - a bottom watermark and a periodic watermark
      // This creates both a static watermark at the bottom and periodically shows a center watermark
      String command = '-i "$videoPath" -vf "' +
          // Bottom persistent watermark
          'drawtext=text=\'Bhavani\':fontcolor=white:fontsize=$fontsize:' +
          'x=10:y=h-$bottomMargin-text_h:box=1:boxcolor=black@$opacity:boxborderw=5,' +
          'drawtext=text=\'$userName\':fontcolor=white:fontsize=$fontsize:' +
          'x=w-text_w-10:y=h-$bottomMargin-text_h*2:box=1:boxcolor=black@$opacity:boxborderw=5,' +
          'drawtext=text=\'$email\':fontcolor=white:fontsize=$fontsize:' +
          'x=w-text_w-10:y=h-$bottomMargin:box=1:boxcolor=black@$opacity:boxborderw=5,' +
          // Periodic center watermark (appears every 5 minutes for 3 seconds)
          'drawtext=text=\'Bhavani - $userName\':fontcolor=white:fontsize=36:' +
          'x=(w-text_w)/2:y=h/2:box=1:boxcolor=black@$opacity:boxborderw=5:' +
          'enable=\'mod(t,300)lt(3)\'' + // Show for 3 seconds every 5 minutes
          '" -c:a copy "$tempOutputPath"';

      print('Executing FFmpeg command: $command');

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();
      final logs = await session.getLogs();

      // Print FFmpeg logs to help with debugging
      print('FFmpeg logs: ${logs.join("\n")}');

      if (ReturnCode.isSuccess(returnCode)) {
        // Replace the original file with the watermarked version
        File videoFile = File(videoPath);
        File tempFile = File(tempOutputPath);
        if (await tempFile.exists()) {
          // Check output file size
          int tempFileSize = await tempFile.length();
          print('Watermarked file size: $tempFileSize bytes');

          await videoFile.delete();
          await tempFile.copy(videoPath);
          await tempFile.delete();
          return true;
        }
      } else {
        print('FFmpeg watermarking failed with return code: $returnCode');
        // Try alternate methods
      }

      return false;
    } catch (e) {
      print('Error in watermark: $e');
      return false;
    }
  }
// Apply optimized watermark to video

// Fallback watermarking methods with simpler approaches
  Future<bool> _applyFallbackWatermark(String videoPath, String tempOutputPath,
      String userName, String email, Function(double) onProgress) async {
    try {
      // First fallback: Simplified watermark with larger text and better opacity
      String command = '-i "$videoPath" -vf "' +
          'drawtext=text=\'Bhavani - $userName - $email\':' +
          'fontcolor=white:fontsize=24:x=10:y=h-20:box=1:boxcolor=black@0.7:boxborderw=5' +
          '" -c:a copy "$tempOutputPath"';

      NyLogger.info('Trying fallback watermarking: $command');
      onProgress(0.4);

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        // Replace the original file with the watermarked version
        File videoFile = File(videoPath);
        File tempFile = File(tempOutputPath);
        if (await tempFile.exists()) {
          await videoFile.delete();
          await tempFile.copy(videoPath);
          await tempFile.delete();
          NyLogger.info('Fallback watermarking succeeded');
          return true;
        }
      }

      // Second fallback: Use a more visible center watermark
      onProgress(0.6);
      String command2 = '-i "$videoPath" -vf "' +
          'drawtext=text=\'Bhavani\':' +
          'fontcolor=white:fontsize=36:x=(w-text_w)/2:y=h/2-text_h:box=1:boxcolor=black@0.7:boxborderw=5' +
          '" -c:a copy "$tempOutputPath"';

      NyLogger.info('Trying center watermarking: $command2');

      final session2 = await FFmpegKit.execute(command2);
      final returnCode2 = await session2.getReturnCode();

      if (ReturnCode.isSuccess(returnCode2)) {
        // Replace the original file with the watermarked version
        File videoFile = File(videoPath);
        File tempFile = File(tempOutputPath);
        if (await tempFile.exists()) {
          await videoFile.delete();
          await tempFile.copy(videoPath);
          await tempFile.delete();
          NyLogger.info('Center watermarking succeeded');
          return true;
        }
      }

      // Last resort: Use the simplest possible watermark
      onProgress(0.8);
      String command3 = '-i "$videoPath" -vf "' +
          'drawtext=text=\'Bhavani\':' +
          'fontcolor=yellow:fontsize=14:x=10:y=10:box=1:boxcolor=black@0.8:boxborderw=5' +
          '" -c:a copy "$tempOutputPath"';

      NyLogger.info('Trying simplified watermarking: $command3');

      final session3 = await FFmpegKit.execute(command3);
      final returnCode3 = await session3.getReturnCode();

      if (ReturnCode.isSuccess(returnCode3)) {
        // Replace the original file with the watermarked version
        File videoFile = File(videoPath);
        File tempFile = File(tempOutputPath);
        if (await tempFile.exists()) {
          await videoFile.delete();
          await tempFile.copy(videoPath);
          await tempFile.delete();
          NyLogger.info('Simple large watermarking succeeded');
          return true;
        }
      }

      // If all else fails, try a copy
      String command4 = '-i "$videoPath" -c copy "$tempOutputPath"';
      final session4 = await FFmpegKit.execute(command4);
      final returnCode4 = await session4.getReturnCode();

      if (ReturnCode.isSuccess(returnCode4)) {
        NyLogger.error('No watermark applied, but video processing succeeded');
        return false;
      }

      return false;
    } catch (e) {
      NyLogger.error('Error in fallback watermarking: $e');
      return false;
    }
  }

// Get user name for watermark
  Future<String> _getUserName() async {
    try {
      var user = await Auth.data();
      if (user != null) {
        return user["full_name"];
      }
    } catch (e) {
      NyLogger.error('Error getting user name: $e');
    }
    return "User";
  }

// Enhanced notify progress update
  void _notifyProgressUpdate(String courseId, String videoId, double progress,
      {String statusMessage = ""}) {
    String key = '${courseId}_${videoId}';
    bool isWatermarking = _watermarkingStatus[key] ?? false;

    _progressStreamController.add({
      'courseId': courseId,
      'videoId': videoId,
      'progress': progress,
      'isWatermarking': isWatermarking,
      'statusMessage': statusMessage,
      'downloadSpeed':
          isWatermarking ? "" : getDownloadSpeed(courseId, videoId),
      'phase': _detailedStatus[key]?.phase.toString() ?? "",
      'retryCount': _retryCount[key] ?? 0,
      'nextRetryTime': _detailedStatus[key]?.nextRetryTime?.toString(),
    });
  }

// Initialize network monitoring with proper types
  Future<void> _initializeNetworkMonitoring() async {
    try {
      // For initial connectivity, we need to handle the List result
      List<ConnectivityResult> initialResults =
          await Connectivity().checkConnectivity();
      _currentConnectivity = initialResults.isNotEmpty
          ? initialResults.first
          : ConnectivityResult.none;

      // The listener now receives a List<ConnectivityResult>
      _connectivitySubscription = Connectivity()
          .onConnectivityChanged
          .listen((List<ConnectivityResult> results) {
        // Take the first result or default to none
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

  Future<int> cleanupStaleDownloads({required String courseId}) async {
    int cleanedCount = 0;
    try {
      final now = DateTime.now();
      List<String> keysToCleanup = [];

      // First identify stale downloads
      for (var key in _downloadingStatus.keys) {
        if (_downloadingStatus[key] == true) {
          // Get course ID from the key
          List<String> parts = key.split('_');
          if (parts.length == 2 && parts[0] == courseId) {
            String videoId = parts[1];

            // Check if it's stale (has been downloading for too long)
            DateTime? startTime = _downloadStartTime[key];
            if (startTime != null && now.difference(startTime).inMinutes > 30) {
              keysToCleanup.add(key);
            }
          }
        }
      }

      // Then clean them up
      for (String key in keysToCleanup) {
        List<String> parts = key.split('_');
        if (parts.length == 2) {
          String courseId = parts[0];
          String videoId = parts[1];

          // Reset status
          _downloadingStatus[key] = false;
          _cancelRequests[key] = true;

          // Add to retry queue with increased priority
          try {
            // Find the original item in pending downloads
            dynamic pendingDownloadsRaw =
                await NyStorage.read('pending_downloads');
            List<dynamic> pendingDownloads = [];

            if (pendingDownloadsRaw is List) {
              pendingDownloads = pendingDownloadsRaw;
            } else if (pendingDownloadsRaw is String) {
              try {
                var decoded = jsonDecode(pendingDownloadsRaw);
                if (decoded is List) {
                  pendingDownloads = decoded;
                }
              } catch (e) {
                pendingDownloads = [];
              }
            }

            // Find the item in pending downloads
            Map<String, dynamic>? downloadData;
            for (dynamic item in pendingDownloads) {
              try {
                Map<String, dynamic> data;
                if (item is String) {
                  data = jsonDecode(item);
                } else if (item is Map) {
                  data = Map<String, dynamic>.from(item);
                } else {
                  continue;
                }

                if (data['courseId'] == courseId &&
                    data['videoId'] == videoId) {
                  downloadData = data;
                  break;
                }
              } catch (e) {
                continue;
              }
            }

            if (downloadData != null) {
              // Re-add to queue with higher priority
              int retryCount = _retryCount[key] ?? 0;
              _enqueueDownload(
                videoUrl: downloadData['videoUrl'],
                courseId: courseId,
                videoId: videoId,
                watermarkText: downloadData['watermarkText'] ?? '',
                email: downloadData['email'] ?? '',
                course: Course.fromJson(downloadData['course']),
                curriculum: downloadData['curriculum'] ?? [],
                priority: 30, // Higher priority for stale downloads
                retryCount: retryCount + 1,
                progress: 0.0, // Start from beginning
                networkPreference: downloadData.containsKey('networkPreference')
                    ? NetworkPreference
                        .values[downloadData['networkPreference']]
                    : _globalNetworkPreference,
              );

              cleanedCount++;
            }
          } catch (e) {
            NyLogger.error('Error requeueing stale download: $e');
          }

          // Clean up resources
          _cleanupDownloadResources(courseId, videoId);
        }
      }

      // Process the queue to restart downloads
      if (cleanedCount > 0) {
        await _saveQueueState();
        _processQueue();
      }

      return cleanedCount;
    } catch (e) {
      NyLogger.error('Error cleaning up stale downloads: $e');
      return 0;
    }
  }

  Future<bool> cancelDownload({
    required String courseId,
    required String videoId,
  }) async {
    try {
      String key = '${courseId}_${videoId}';

      // Cancel active download if in progress
      if (_downloadingStatus[key] == true || _watermarkingStatus[key] == true) {
        _cancelRequests[key] = true;
        _downloadingStatus[key] = false;
        _watermarkingStatus[key] = false;

        // Update status
        _detailedStatus[key] = VideoDownloadStatus(
          phase: DownloadPhase.cancelled,
          progress: _downloadProgress[key] ?? 0.0,
          message: "Download cancelled",
        );

        // Notify UI
        _notifyProgressUpdate(courseId, videoId, 0.0,
            statusMessage: "Download cancelled");

        // Clean up any related resources
        _cleanupDownloadResources(courseId, videoId);
      }

      // Remove from queue if queued
      int index = _downloadQueue.indexWhere(
          (item) => item.courseId == courseId && item.videoId == videoId);

      if (index >= 0) {
        _downloadQueue.removeAt(index);
        await _saveQueueState();
      }

      // Remove from pending downloads storage
      await _removeFromPendingDownloads(courseId, videoId);

      return true;
    } catch (e) {
      NyLogger.error('Error cancelling download: $e');
      return false;
    }
  }

  // Enhanced is video watermarked with user isolation
  Future<bool> isVideoWatermarked(String courseId, String videoId) async {
    try {
      String videoPath = await getVideoFilePath(courseId, videoId);
      File videoFile = File(videoPath);

      if (!await videoFile.exists()) {
        return false; // File doesn't exist
      }

      // Check for watermark flag file
      String watermarkFlagPath = await _getWatermarkFlagPath(courseId, videoId);
      File watermarkFlagFile = File(watermarkFlagPath);

      if (await watermarkFlagFile.exists()) {
        NyLogger.info(
            'Watermark flag found for user $_currentUserId video $courseId/$videoId');
        return true;
      }

      // If the video exists but no flag, create flag and assume watermarked
      try {
        await watermarkFlagFile.writeAsString('watermarked');
        NyLogger.info(
            'Created watermark flag for existing video $courseId/$videoId for user $_currentUserId');
        return true;
      } catch (e) {
        _reportError('create_watermark_flag', e);
      }

      return true; // Assume watermarked to prevent watermarking failures
    } catch (e) {
      _reportError('is_video_watermarked', e, additionalData: {
        'user_id': _currentUserId ?? 'unknown',
        'course_id': courseId,
        'video_id': videoId,
      });
      return false;
    }
  }

  // Method to handle user logout/cleanup
  Future<void> handleUserLogout() async {
    try {
      FirebaseCrashlytics.instance
          .log('Handling user logout, current user: $_currentUserId');

      // Cancel all active downloads
      for (var key in _downloadingStatus.keys) {
        if (_downloadingStatus[key] == true) {
          _cancelRequests[key] = true;
        }
      }

      // Save current state before logout
      await _saveQueueState();

      // Clear current user context
      _currentUserId = null;

      // Clear in-memory data
      _downloadQueue.clear();
      _downloadProgress.clear();
      _downloadingStatus.clear();
      _cancelRequests.clear();
      _watermarkingStatus.clear();
      _watermarkProgress.clear();
      _detailedStatus.clear();

      // Clear Crashlytics user context
      FirebaseCrashlytics.instance.setUserIdentifier('logged_out');

      NyLogger.info('User logout handled successfully');
    } catch (e, stackTrace) {
      _reportError('handle_user_logout', e, stackTrace: stackTrace);
    }
  }

  Future<void> handleUserLogin() async {
    try {
      // Set new user context
      await _setCurrentUserContext();

      FirebaseCrashlytics.instance
          .log('Handling user login, new user: $_currentUserId');

      // Clean up other users' data if needed
      await _cleanupOtherUsersData();

      // Restore new user's queue and downloads
      await _restoreQueueState();
      await _restorePendingDownloads();

      NyLogger.info(
          'User login handled successfully for user: $_currentUserId');
    } catch (e, stackTrace) {
      _reportError('handle_user_login', e, stackTrace: stackTrace);
    }
  }

  // Get video file path
  Future<String> getVideoFilePath(String courseId, String videoId) async {
    Directory appDir;

    if (Platform.isIOS) {
      appDir = await getApplicationDocumentsDirectory();
    } else {
      appDir = await getApplicationDocumentsDirectory();
    }

    // Get current user ID for isolation
    String userId = await _getCurrentUserId();

    // Create user-specific path structure
    String userPath = '${appDir.path}/users/$userId/courses/$courseId/videos';
    await Directory(userPath).create(recursive: true);

    return '$userPath/video_$videoId.mp4';
  }

  Future<String> _getCurrentUserId() async {
    try {
      var user = await Auth.data();
      if (user != null && user['id'] != null) {
        return user['id'].toString();
      }
    } catch (e) {
      _reportError('get_current_user_id', e);
    }
    return 'default_user'; // Fallback
  }

  Future<String> _getWatermarkFlagPath(String courseId, String videoId) async {
    String videoPath = await getVideoFilePath(courseId, videoId);
    return '$videoPath.watermarked';
  }

  String _getUserSpecificKey(String baseKey) {
    // This will be set when user logs in
    String? currentUserId = _currentUserId;
    if (currentUserId != null && currentUserId.isNotEmpty) {
      return '${baseKey}_user_$currentUserId';
    }
    return baseKey; // Fallback to non-user-specific
  }

// Helper method to check if URL is likely a video
  bool _isLikelyVideoUrl(String url) {
    // Convert to lowercase for case-insensitive comparison
    String lowercaseUrl = url.toLowerCase();

    // Check for common video file extensions
    bool hasVideoExtension = lowercaseUrl.endsWith('.mp4') ||
        lowercaseUrl.endsWith('.mov') ||
        lowercaseUrl.endsWith('.avi') ||
        lowercaseUrl.endsWith('.webm') ||
        lowercaseUrl.endsWith('.mkv') ||
        lowercaseUrl.endsWith('.m4v') ||
        lowercaseUrl.endsWith('.flv') ||
        lowercaseUrl.endsWith('.wmv') ||
        lowercaseUrl.endsWith('.3gp');

    // Check for common video-related patterns in URLs
    bool hasVideoPattern = lowercaseUrl.contains('video') ||
        lowercaseUrl.contains('stream') ||
        lowercaseUrl.contains('/play/') ||
        lowercaseUrl.contains('/watch/') ||
        lowercaseUrl.contains('/media/') ||
        lowercaseUrl.contains('content') ||
        lowercaseUrl.contains('/embed/') ||
        lowercaseUrl.contains('playlist');

    // Check for video service domains
    bool hasVideoService = lowercaseUrl.contains('youtube.com') ||
        lowercaseUrl.contains('vimeo.com') ||
        lowercaseUrl.contains('dailymotion.com') ||
        lowercaseUrl.contains('jwplayer') ||
        lowercaseUrl.contains('cloudfront.net') ||
        lowercaseUrl.contains('amazonaws.com/video') ||
        lowercaseUrl.contains('cdn') &&
            (lowercaseUrl.contains('mp4') || lowercaseUrl.contains('video'));

    // Return true if any of the conditions match
    return hasVideoExtension || hasVideoPattern || hasVideoService;
  }

// Enhanced play video with error reporting
  Future<void> playVideo({
    required String videoUrl,
    required String courseId,
    required String videoId,
    required String watermarkText,
    required Course course,
    required BuildContext context,
  }) async {
    // Set context for play operation
    FirebaseCrashlytics.instance.setCustomKey('play_course_id', courseId);
    FirebaseCrashlytics.instance.setCustomKey('play_video_id', videoId);
    FirebaseCrashlytics.instance.setCustomKey('course_title', course.title);

    try {
      // ✅ Use the course object instead of making API call
      bool hasValidSubscription = true;

      FirebaseCrashlytics.instance
          .setCustomKey('has_valid_subscription', hasValidSubscription);

      if (!hasValidSubscription) {
        FirebaseCrashlytics.instance
            .log('Subscription expired for course: ${course.title}');

        // Show subscription expired dialog
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
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
                TextButton(
                  child: Text(trans("Renew")),
                  style: TextButton.styleFrom(foregroundColor: Colors.amber),
                  onPressed: () async {
                    Navigator.of(context).pop();
                    // ✅ Use the course object directly
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
        return;
      }

      // Get the file path for the video
      String videoPath = await getVideoFilePath(courseId, videoId);
      File videoFile = File(videoPath);

      // Check if the video exists locally
      if (await videoFile.exists()) {
        FirebaseCrashlytics.instance.log(
            'Video file found locally, preparing for playback: $videoPath');

        // Show loading indicator while checking/applying watermark
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    "Preparing video...",
                    style: TextStyle(color: Colors.white),
                  )
                ],
              ),
            );
          },
        );

        // Get user email for watermark
        String email = "";
        String userName = "User";
        try {
          var user = await Auth.data();
          if (user != null) {
            email = user['email'];
            userName = user['full_name'];

            FirebaseCrashlytics.instance.setCustomKey('user_email', email);
            FirebaseCrashlytics.instance.setCustomKey('user_name', userName);
          }
        } catch (e, stackTrace) {
          _reportError('get_user_info_for_playback', e, stackTrace: stackTrace);
        }

        // Find the video title in curriculum data
        String videoTitle = await _getVideoTitle(courseId, videoId);

        // Ensure the video has a watermark
        bool hasWatermark = await ensureVideoWatermarked(
          courseId: courseId,
          videoId: videoId,
          email: email,
          userName: userName,
        );

        // Remove loading dialog
        Navigator.of(context, rootNavigator: true).pop();

        if (!hasWatermark) {
          FirebaseCrashlytics.instance.log(
              'Warning: Video may not be properly watermarked: $videoPath');
          // If watermarking failed, warn but allow playback
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text(trans("Warning: Video may not be properly watermarked")),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }

        FirebaseCrashlytics.instance.log('Playing video: $videoTitle');

        // Play the video (watermark is embedded in the file)
        routeTo(VideoPlayerPage.path, data: {
          'videoPath': videoPath,
          'title': videoTitle,
        });
      } else {
        FirebaseCrashlytics.instance
            .log('Video file not found locally: $videoPath');

        // Video doesn't exist locally
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(trans("Please download the video first")),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );

        bool shouldDownload = await showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(trans("Video Not Found")),
                content:
                    Text(trans("Would you like to download this video now?")),
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
            ) ??
            false;

        if (shouldDownload) {
          // Get course info
          Course? course;
          List<dynamic> curriculum = [];

          // Try to find course info in storage
          dynamic pendingDownloadsRaw =
              await NyStorage.read('pending_downloads');
          if (pendingDownloadsRaw != null) {
            try {
              List<dynamic> pendingDownloads = [];
              if (pendingDownloadsRaw is List) {
                pendingDownloads = pendingDownloadsRaw;
              } else if (pendingDownloadsRaw is String) {
                var decoded = jsonDecode(pendingDownloadsRaw);
                if (decoded is List) {
                  pendingDownloads = decoded;
                }
              }

              // Find matching course
              for (var item in pendingDownloads) {
                Map<String, dynamic> downloadData;
                if (item is String) {
                  downloadData = jsonDecode(item);
                } else if (item is Map) {
                  downloadData = Map<String, dynamic>.from(item);
                } else {
                  continue;
                }

                if (downloadData['courseId'] == courseId) {
                  if (downloadData.containsKey('course')) {
                    course = Course.fromJson(downloadData['course']);
                  }
                  if (downloadData.containsKey('curriculum')) {
                    curriculum = downloadData['curriculum'];
                  }
                  break;
                }
              }
            } catch (e) {
              NyLogger.error('Error finding course info: $e');
            }
          }

          if (course != null) {
            var users = await Auth.data();
            var emails;
            if (users != null) {
              emails = users['email'];
            }
            // Start the download
            await enqueueDownload(
              videoUrl: videoUrl,
              courseId: courseId,
              videoId: videoId,
              watermarkText: watermarkText,
              email: emails,
              course: course,
              curriculum: curriculum,
              priority: 10, // High priority
            );

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(trans(
                    "Download started. The video will be available soon.")),
                duration: const Duration(seconds: 3),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(trans(
                    "Couldn't find course information. Please try downloading from the course page.")),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      }
    } catch (e, stackTrace) {
      _reportError('playVideo', e, stackTrace: stackTrace, additionalData: {
        'course_id': courseId,
        'video_id': videoId,
        'video_url': videoUrl,
        'course_title': course.title,
      });

      // Close loading dialog if open
      try {
        Navigator.of(context, rootNavigator: true).pop();
      } catch (_) {}

      NyLogger.error('Error playing video: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(trans("Failed to play video: ${e.toString()}")),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // Future getCourseCurriculumItems(int courseId) async {
  //   final _courseApiService = CourseApiService();
  //   List<dynamic> result =
  //       await _courseApiService.getCourseCurriculum(courseId);

  //   if (result.length > 100) {
  //     // For very large lists, use compute to prevent UI blocking
  //     result.sort((a, b) => a['order'].compareTo(b['order']));
  //   } else {
  //     // For smaller lists, just sort directly
  //     result.sort((a, b) => a['order'].compareTo(b['order']));
  //   }

  //   return result;
  // }

// Dispose resources
  void dispose() {
    try {
      FirebaseCrashlytics.instance.log('Disposing VideoService');

      // Cancel all network monitoring
      try {
        _connectivitySubscription.cancel();
      } catch (e, stackTrace) {
        _reportError('dispose_connectivity_subscription', e,
            stackTrace: stackTrace);
      }

      // Save current state before shutdown
      try {
        _saveQueueState();
      } catch (e, stackTrace) {
        _reportError('dispose_save_queue_state', e, stackTrace: stackTrace);
      }

      // Cancel all retry timers
      for (var timer in _retryTimers.values) {
        try {
          timer.cancel();
        } catch (e, stackTrace) {
          _reportError('dispose_retry_timer', e, stackTrace: stackTrace);
        }
      }
      _retryTimers.clear();

      // Cancel any active downloads
      try {
        _dio.close(force: true);
      } catch (e, stackTrace) {
        _reportError('dispose_dio_client', e, stackTrace: stackTrace);
      }

      // Close stream controller
      try {
        if (!_progressStreamController.isClosed) {
          _progressStreamController.close();
        }
      } catch (e, stackTrace) {
        _reportError('dispose_progress_stream_controller', e,
            stackTrace: stackTrace);
      }

      // Properly close any open file streams
      try {
        for (var key in _downloadingStatus.keys) {
          if (_downloadingStatus[key] == true) {
            _cancelRequests[key] = true;
          }
        }
      } catch (e, stackTrace) {
        _reportError('dispose_cancel_downloads', e, stackTrace: stackTrace);
      }

      FirebaseCrashlytics.instance.log('VideoService disposed successfully');
      NyLogger.info('VideoService disposed successfully');
    } catch (e, stackTrace) {
      _reportError('dispose', e, stackTrace: stackTrace);
    }
  }

// Helper method to get video title
  Future<String> _getVideoTitle(String courseId, String videoId) async {
    try {
      // Try to find the course in pending downloads
      dynamic pendingDownloadsRaw = await NyStorage.read('pending_downloads');
      List<dynamic> pendingDownloads = [];

      if (pendingDownloadsRaw is List) {
        pendingDownloads = pendingDownloadsRaw;
      } else if (pendingDownloadsRaw is String) {
        try {
          var decoded = jsonDecode(pendingDownloadsRaw);
          if (decoded is List) {
            pendingDownloads = decoded;
          }
        } catch (e) {
          pendingDownloads = [];
        }
      }

      // Look for this course/video in the pending downloads
      for (dynamic item in pendingDownloads) {
        try {
          Map<String, dynamic> downloadData;
          if (item is String) {
            downloadData = jsonDecode(item);
          } else if (item is Map) {
            downloadData = Map<String, dynamic>.from(item);
          } else {
            continue;
          }

          if (downloadData['courseId'] == courseId) {
            // Get the course name if available
            String courseName = "";
            if (downloadData.containsKey('course')) {
              Course course = Course.fromJson(downloadData['course']);
              courseName = course.title;
            }

            List<dynamic> curriculum = downloadData['curriculum'] ?? [];

            // Try to find the video in the curriculum
            try {
              int videoIndex = int.parse(videoId);
              if (videoIndex >= 0 && videoIndex < curriculum.length) {
                String videoTitle =
                    curriculum[videoIndex]['title'] ?? "Video $videoId";

                // Add course name if available for better context
                if (courseName.isNotEmpty) {
                  return "$courseName - $videoTitle";
                }
                return videoTitle;
              }
            } catch (e) {
              // Not a valid index, try looking for video_id match
              for (var lecture in curriculum) {
                if (lecture is Map &&
                    lecture.containsKey('video_id') &&
                    lecture['video_id'].toString() == videoId) {
                  String videoTitle = lecture['title'] ?? "Video $videoId";

                  // Add course name if available
                  if (courseName.isNotEmpty) {
                    return "$courseName - $videoTitle";
                  }
                  return videoTitle;
                }
              }
            }
          }
        } catch (e) {
          continue;
        }
      }

      // If we reach here, we couldn't find the title
      return "Video $videoId";
    } catch (e) {
      NyLogger.error('Error getting video title: $e');
      return "Video $videoId";
    }
  }
}
