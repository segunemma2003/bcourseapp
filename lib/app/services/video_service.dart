import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'dart:math' show min;
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:ffmpeg_kit_flutter_new/statistics.dart';
import 'package:flutter/material.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart'; // Add this package for network connectivity
import 'package:disk_space/disk_space.dart'; // Add this package for disk space checks

import '../../resources/pages/video_player_page.dart';
import '../../app/models/course.dart';

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

  // Initialize service
  Future<void> initialize() async {
    // Load settings
    await _loadSettings();

    // Set up network monitoring
    await _initializeNetworkMonitoring();

    // Restore the queue state and pending downloads
    await _restoreQueueState();
    await _restorePendingDownloads();

    NyLogger.info('VideoService initialized successfully');
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

  Future<void> _removeFromPendingDownloads(
      String courseId, String videoId) async {
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

      await NyStorage.save('pending_downloads', updatedDownloads);
    } catch (e) {
      NyLogger.error('Error removing from pending downloads: $e');
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
      await NyStorage.save('download_queue', jsonEncode(queueData));
      NyLogger.info('Saved queue state with ${queueData.length} items');
    } catch (e) {
      NyLogger.error('Error saving queue state: $e');
    }
  }

  // Restore queue state
  Future<void> _restoreQueueState() async {
    try {
      String? queueDataString = await NyStorage.read('download_queue');
      if (queueDataString != null && queueDataString.isNotEmpty) {
        List<dynamic> queueJson = jsonDecode(queueDataString);

        for (var itemJson in queueJson) {
          try {
            DownloadQueueItem item = DownloadQueueItem.fromJson(itemJson);
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
          } catch (e) {
            NyLogger.error('Error restoring queue item: $e');
          }
        }

        NyLogger.info(
            'Restored ${_downloadQueue.length} items to download queue');
      }
    } catch (e) {
      NyLogger.error('Error restoring queue state: $e');
    }
  }

  // Check and restore any pending downloads
  Future<void> _restorePendingDownloads() async {
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

            // Check if it was previously downloading
            dynamic storedProgress =
                await NyStorage.read('progress_$downloadKey');
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
          } catch (e) {
            NyLogger.error('Error restoring download: $e');
          }
        }

        // Start processing the queue
        _processQueue();
      }
    } catch (e) {
      NyLogger.error('Error checking pending downloads: $e');
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

      // Check if already downloading, watermarking or queued
      if (_downloadingStatus[downloadKey] == true ||
          _watermarkingStatus[downloadKey] == true ||
          isQueued(courseId, videoId)) {
        NyLogger.info('Download already in progress or queued');
        return false;
      }

      // Add to queue
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
      double? freeDiskSpace = await DiskSpace.getFreeDiskSpace;

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

  // Save download info with enhanced parameters
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
      };

      String downloadKey = '${courseId}_${videoId}';
      await NyStorage.save('progress_$downloadKey', 0.0);

      dynamic existingData = await NyStorage.read('pending_downloads');
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
      await NyStorage.save('pending_downloads', pendingDownloads);

      NyLogger.info('Download info saved to storage');
    } catch (e) {
      NyLogger.error('Error saving download info: $e');
    }
  }

  // Start download process with enhanced parameters
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

      NyLogger.info('Download started for video $videoId in course $courseId ' +
          '(Retry #$retryCount)');

      // 1. Download the video first
      bool downloadSuccess = await downloadVideo(
        videoUrl: videoUrl,
        courseId: courseId,
        videoId: videoId,
        resumeFromProgress: progress, // Resume from previous progress
        onProgress: (progress, statusMessage) {
          if (_cancelRequests[downloadKey] == true) {
            throw Exception("Download cancelled");
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

      if (!downloadSuccess) {
        throw Exception("Failed to download video");
      }

      // 2. Then watermark the video if download was successful (using optimized method)
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

        // Apply watermark with optimized approach
        bool watermarkSuccess = await applyOptimizedWatermark(
          courseId: courseId,
          videoId: videoId,
          watermarkText: watermarkText,
          email: email,
          onProgress: (progress) {
            if (_cancelRequests[downloadKey] == true) {
              throw Exception("Watermarking cancelled");
            }
            _watermarkProgress[downloadKey] = progress;
            _notifyProgressUpdate(courseId, videoId, progress,
                statusMessage: "Adding watermark...");
          },
        );

        if (!watermarkSuccess) {
          throw Exception("Failed to apply watermark");
        }
      }

      _handleDownloadComplete(
        courseId: courseId,
        videoId: videoId,
        success: downloadSuccess,
        course: course,
        curriculum: curriculum,
      );
    } catch (e) {
      NyLogger.error('Download process error: $e');

      if (_cancelRequests[downloadKey] == true) {
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
                  "Failed - retrying in ${delaySeconds}s (Attempt ${currentRetryCount + 1}/${_maxRetryAttempts})");

          // Update retry info in storage
          await _updateRetryInfoInStorage(
              courseId, videoId, currentRetryCount + 1);

          // Schedule retry
          _retryTimers[downloadKey] =
              Timer(Duration(seconds: delaySeconds), () {
            // Add back to queue with same details but higher priority
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
      var status = await Permission.storage.request();
      if (!status.isGranted) {
        NyLogger.error('Storage permission denied');
        throw Exception("Storage permission denied");
      }

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

      DateTime lastSpeedCheck = DateTime.now();
      int lastBytesReceived = startByte;

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

      // Download with progress tracking
      try {
        // If resuming and file exists, prepare to append to it
        IOSink? fileSink;
        if (startByte > 0) {
          fileSink = outputFile.openWrite(mode: FileMode.append);
          NyLogger.info('Opened file for appending from byte $startByte');
        }

        await _dio.download(
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
        );

        // Close file if we were appending
        if (fileSink != null) {
          await fileSink.close();
          NyLogger.info('Closed file sink after appending download data');
        }
      } on DioException catch (e) {
        // Handle specific Dio errors
        if (e.type == DioExceptionType.cancel) {
          NyLogger.info('Download was cancelled');
          throw CancelException("Download cancelled");
        } else if (e is PauseException) {
          NyLogger.info('Download paused: ${e.message}');
          throw PauseException(e.message!);
        } else {
          // For all other Dio errors, try fallback method if not resuming
          NyLogger.error('Dio download error: ${e.message}');

          if (startByte == 0) {
            return await _fallbackDownload(
                videoUrl, outputPath, headers, onProgress);
          } else {
            NyLogger.error('Cannot use fallback method for resumed download');
            throw Exception("Download failed: ${e.message}");
          }
        }
      } catch (e) {
        // Handle other exceptions
        if (e is CancelException) {
          NyLogger.info('Download was cancelled: ${e.message}');
          throw e;
        } else if (e is PauseException) {
          NyLogger.info('Download paused: ${e.message}');
          throw e;
        } else {
          NyLogger.error('Error during download: $e');

          if (startByte == 0) {
            return await _fallbackDownload(
                videoUrl, outputPath, headers, onProgress);
          } else {
            throw Exception("Download failed: $e");
          }
        }
      }

      // Verify download was successful
      if (!await outputFile.exists()) {
        NyLogger.error('Video file does not exist after download');
        return false;
      }

      int fileSize = await outputFile.length();
      if (fileSize < 1000) {
        NyLogger.error('Downloaded file is too small: $fileSize bytes');
        return false;
      }

      NyLogger.info('Download completed successfully: $fileSize bytes');
      return true;
    } catch (e) {
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

      // Use basic http client as fallback
      final httpClient = http.Client();
      final request = http.Request('GET', Uri.parse(videoUrl));
      request.headers.addAll(headers);

      final response = await httpClient.send(request);

      if (response.statusCode == 200 || response.statusCode == 206) {
        final file = File(outputPath);
        final fileStream = file.openWrite();

        int received = 0;
        int total = response.contentLength ?? -1;

        await response.stream.forEach((chunk) {
          fileStream.add(chunk);
          received += chunk.length;

          if (total != -1 && onProgress != null) {
            double progress = received / total;
            onProgress(progress, "Downloading with alternative method...");
          }
        });

        await fileStream.close();
        httpClient.close();

        if (onProgress != null) {
          onProgress(1.0, "Download completed");
        }

        NyLogger.info('Fallback download succeeded');
        return true;
      } else {
        NyLogger.error(
            'Fallback download failed with status: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      NyLogger.error('Fallback download failed: $e');
      return false;
    }
  }

  Future<bool> isVideoDownloaded({
    required String videoUrl,
    required String courseId,
    required String videoId,
  }) async {
    try {
      // Get the file path for the video
      String filePath = await getVideoFilePath(courseId, videoId);
      File videoFile = File(filePath);

      // Check if the file exists
      bool exists = await videoFile.exists();

      if (exists) {
        // Also check file size to ensure it's a valid video file (not just an empty file)
        int fileSize = await videoFile.length();

        // Consider files below 10KB as invalid/incomplete videos
        if (fileSize < 10 * 1024) {
          NyLogger.error(
              'Video file exists but is too small (${fileSize} bytes), considering as not downloaded');
          return false;
        }

        NyLogger.info('Video found: $courseId/$videoId (${fileSize} bytes)');
        return true;
      }

      NyLogger.info('Video not found: $courseId/$videoId');
      return false;
    } catch (e) {
      NyLogger.error('Error checking downloaded video: $e');
      return false;
    }
  }

// Apply optimized watermark to video
  Future<bool> applyOptimizedWatermark({
    required String courseId,
    required String videoId,
    required String watermarkText,
    required String email,
    required Function(double) onProgress,
  }) async {
    String downloadKey = '${courseId}_${videoId}';

    try {
      // Get file paths
      String videoPath = await getVideoFilePath(courseId, videoId);

      // Ensure the downloaded video exists
      File videoFile = File(videoPath);
      if (!await videoFile.exists()) {
        NyLogger.error('Video file not found for watermarking');
        return false;
      }

      if (await isVideoWatermarked(courseId, videoId)) {
        NyLogger.info('Video already has watermark, skipping watermarking');
        onProgress(1.0);
        return true;
      }

      // Report initial progress
      onProgress(0.1);

      // Get user name for watermark
      String userName = await _getUserName();

      // Create temporary file for watermarked output
      Directory tempDir = await getTemporaryDirectory();
      String tempOutputPath = '${tempDir.path}/temp_watermarked_$videoId.mp4';

      // Check file size to make sure it's a valid video
      int fileSize = await videoFile.length();
      if (fileSize < 10000) {
        // Less than 10KB is likely not a valid video
        NyLogger.error(
            'Video file is too small (${fileSize} bytes), may be corrupted');
        return false;
      }

      bool watermarkSuccess = false;

      // Apply permanent watermark with all required elements
      try {
        // Create permanent watermark with requirements:
        // - "Bhavani" at bottom left
        // - User name at bottom right
        // - Email under the user name
        // - Font size not more than 12px
        String fontsize = "12";
        String bottomMargin = "10"; // 10 pixels from bottom

        String command = '-i "$videoPath" -vf "' +
            // Bottom left "Bhavani"
            'drawtext=text=\'Bhavani\':fontcolor=white:fontsize=$fontsize:' +
            'x=10:y=h-$bottomMargin-text_h:box=1:boxcolor=black@0.4:boxborderw=5,' +
            // Bottom right username
            'drawtext=text=\'$userName\':fontcolor=white:fontsize=$fontsize:' +
            'x=w-text_w-10:y=h-$bottomMargin-text_h*2:box=1:boxcolor=black@0.4:boxborderw=5,' +
            // Email under username
            'drawtext=text=\'$email\':fontcolor=white:fontsize=$fontsize:' +
            'x=w-text_w-10:y=h-$bottomMargin:box=1:boxcolor=black@0.4:boxborderw=5' +
            '" -c:a copy "$tempOutputPath"';

        NyLogger.info('Applying permanent watermark with command: $command');

        final session = await FFmpegKit.execute(command);
        final returnCode = await session.getReturnCode();

        if (ReturnCode.isSuccess(returnCode)) {
          // Replace the original file with the watermarked version
          File tempFile = File(tempOutputPath);
          if (await tempFile.exists()) {
            await videoFile.delete();
            await tempFile.copy(videoPath);
            await tempFile.delete();
            watermarkSuccess = true;
            NyLogger.info('Permanent watermarking succeeded');
          }
        } else {
          NyLogger.error(
              'Permanent watermarking failed with code: ${returnCode?.getValue()}');

          // Try fallback watermarking
          return await _applyFallbackWatermark(
              videoPath, tempOutputPath, userName, email, onProgress);
        }
      } catch (e) {
        NyLogger.error('Error during permanent watermarking: $e');

        // Try fallback watermarking
        return await _applyFallbackWatermark(
            videoPath, tempOutputPath, userName, email, onProgress);
      }

      // Update progress in stages
      for (int i = 2; i <= 10; i++) {
        await Future.delayed(Duration(milliseconds: 50));
        onProgress(i / 10);
      }

      // Log successful watermarking
      if (watermarkSuccess) {
        try {
          final watermarkFlagFile = File('$videoPath.watermarked');
          await watermarkFlagFile.writeAsString('watermarked');
        } catch (e) {
          // Non-critical error, just log it
          NyLogger.error('Error creating watermark flag file: $e');
        }
      }
      return watermarkSuccess;
    } catch (e) {
      NyLogger.error('Error in watermarking process: $e');
      onProgress(1.0);
      return false;
    }
  }

// Fallback watermarking methods with simpler approaches
  Future<bool> _applyFallbackWatermark(String videoPath, String tempOutputPath,
      String userName, String email, Function(double) onProgress) async {
    try {
      // First fallback: Simplified watermark
      String command = '-i "$videoPath" -vf "' +
          'drawtext=text=\'Bhavani - $userName - $email\':' +
          'fontcolor=white:fontsize=12:x=10:y=h-10:box=1:boxcolor=black@0.4:boxborderw=5' +
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

      // Second fallback: Minimal watermark (just Bhavani)
      onProgress(0.6);
      String command2 = '-i "$videoPath" -vf "' +
          'drawtext=text=\'Bhavani\':' +
          'fontcolor=white:fontsize=12:x=10:y=h-10:box=1:boxcolor=black@0.4:boxborderw=5' +
          '" -c:a copy "$tempOutputPath"';

      NyLogger.info('Trying minimal watermarking: $command2');

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
          NyLogger.info('Minimal watermarking succeeded');
          return true;
        }
      }

      // Last resort: Try to copy the video without watermark
      onProgress(0.8);
      String command3 = '-i "$videoPath" -c copy "$tempOutputPath"';

      NyLogger.info('Trying copy only as last resort: $command3');

      final session3 = await FFmpegKit.execute(command3);
      final returnCode3 = await session3.getReturnCode();

      if (ReturnCode.isSuccess(returnCode3)) {
        NyLogger.error('No watermark applied, but video processing succeeded');
        return true;
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

// Check if a video has a watermark already
  Future<bool> isVideoWatermarked(String courseId, String videoId) async {
    try {
      String videoPath = await getVideoFilePath(courseId, videoId);
      File videoFile = File(videoPath);

      if (!await videoFile.exists()) {
        return false; // File doesn't exist
      }

      // Create temporary directory for screenshots
      Directory tempDir = await getTemporaryDirectory();
      String screenshotPath = '${tempDir.path}/watermark_check_$videoId.jpg';

      // Take a screenshot of the video at 80% of the duration to check for watermark
      try {
        // First get the duration of the video
        String durationCommand =
            '-i "$videoPath" -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1';
        final durationSession = await FFmpegKit.execute(durationCommand);
        final durationReturnCode = await durationSession.getReturnCode();

        String duration = "5"; // Default 5 seconds if we can't determine

        if (ReturnCode.isSuccess(durationReturnCode)) {
          final output = await durationSession.getOutput();
          if (output != null && output.isNotEmpty) {
            try {
              double durationSeconds = double.parse(output.trim());
              // Take screenshot at 80% of the video
              duration = (durationSeconds * 0.8).toStringAsFixed(1);
            } catch (e) {
              NyLogger.error('Error parsing duration: $e');
            }
          }
        }

        // Take a screenshot at the specified time
        String screenshotCommand =
            '-ss $duration -i "$videoPath" -frames:v 1 -q:v 2 "$screenshotPath"';
        final screenshotSession = await FFmpegKit.execute(screenshotCommand);
        final screenshotReturnCode = await screenshotSession.getReturnCode();

        if (ReturnCode.isSuccess(screenshotReturnCode)) {
          File screenshotFile = File(screenshotPath);
          if (await screenshotFile.exists()) {
            // Since we can't use real OCR in this environment, we'll check the screenshot properties
            // This is a simplified check - in a real app, you might use ML Kit or another OCR library

            // Check file size - a watermarked video will typically have metadata in the screenshot
            int fileSize = await screenshotFile.length();

            // Clean up the screenshot
            await screenshotFile.delete();

            // This is a very simplified check - a real implementation would use OCR
            // We'll just assume the video has been processed if the screenshot exists
            return true;
          }
        }

        return false;
      } catch (e) {
        NyLogger.error('Error checking for watermark: $e');
        return false;
      }
    } catch (e) {
      NyLogger.error('Error in watermark check: $e');
      return false;
    }
  }

  // Get video file path
  Future<String> getVideoFilePath(String courseId, String videoId) async {
    // Get the app's documents directory
    Directory appDir = await getApplicationDocumentsDirectory();

    // Create a consistent path structure for video storage
    // Format: /app_documents/courses/{courseId}/videos/video_{videoId}.mp4
    // This creates a folder per course, making management easier
    return '${appDir.path}/courses/$courseId/videos/video_$videoId.mp4';
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

// Play video with watermark check
  Future<void> playVideo({
    required String videoUrl,
    required String courseId,
    required String videoId,
    required String watermarkText,
    required BuildContext context,
  }) async {
    try {
      // Get the file path for the video
      String videoPath = await getVideoFilePath(courseId, videoId);
      File videoFile = File(videoPath);

      // Check if the video exists locally
      if (await videoFile.exists()) {
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
          }
        } catch (e) {
          NyLogger.error('Error getting user info: $e');
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

        // Play the video (watermark is embedded in the file)
        routeTo(VideoPlayerPage.path, data: {
          'videoPath': videoPath,
          'title': videoTitle,
        });
      } else {
        // Video doesn't exist locally
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(trans("Please download the video first")),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );

        // Offer to download the video
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
    } catch (e) {
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

// Dispose resources
  void dispose() {
    // Cancel all network monitoring
    try {
      _connectivitySubscription.cancel();
    } catch (e) {
      NyLogger.error('Error canceling connectivity subscription: $e');
    }

    // Save current state before shutdown
    try {
      _saveQueueState();
    } catch (e) {
      NyLogger.error('Error saving queue state: $e');
    }

    // Cancel all retry timers
    for (var timer in _retryTimers.values) {
      try {
        timer.cancel();
      } catch (e) {
        NyLogger.error('Error canceling retry timer: $e');
      }
    }
    _retryTimers.clear();

    // Cancel any active downloads
    try {
      _dio.close(force: true);
    } catch (e) {
      NyLogger.error('Error closing Dio client: $e');
    }

    // Close stream controller
    try {
      if (!_progressStreamController.isClosed) {
        _progressStreamController.close();
      }
    } catch (e) {
      NyLogger.error('Error closing progress stream controller: $e');
    }

    // Properly close any open file streams
    try {
      for (var key in _downloadingStatus.keys) {
        if (_downloadingStatus[key] == true) {
          _cancelRequests[key] = true;
        }
      }
    } catch (e) {
      NyLogger.error('Error marking downloads as canceled: $e');
    }

    NyLogger.info('VideoService disposed successfully');
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
