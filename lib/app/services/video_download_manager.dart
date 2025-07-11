// TODO Implement this library.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_app/app/models/course.dart';
import 'package:flutter_app/app/services/video_storage_manager.dart';
import 'package:flutter_app/app/services/video_watermark_manager.dart';
import 'package:flutter_app/app/services/video_service_utils.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'package:http/http.dart' as http;

class VideoDownloadManager {
  final VideoStorageManager storageManager;
  final VideoWatermarkManager watermarkManager;
  final StreamController<Map<String, dynamic>> progressStreamController;

  // Download queue and status tracking
  final List<DownloadQueueItem> _downloadQueue = [];
  bool _isProcessingQueue = false;
  int _maxConcurrentDownloads = 2;
  int _activeDownloads = 0;

  // Progress and status tracking
  final Map<String, double> _downloadProgress = {};
  final Map<String, bool> _downloadingStatus = {};
  final Map<String, bool> _cancelRequests = {};
  final Map<String, bool> _watermarkingStatus = {};
  final Map<String, double> _watermarkProgress = {};
  final Map<String, VideoDownloadStatus> _detailedStatus = {};

  final List<DownloadQueueItem> _highPriorityQueue = [];
  final List<DownloadQueueItem> _normalPriorityQueue = [];
  final List<DownloadQueueItem> _lowPriorityQueue = [];

  // Per-queue processing locks
  final Map<String, bool> _queueProcessingLocks = {};

  // Dynamic concurrent limit based on network speed
  int _dynamicConcurrentLimit = 2;

  // Download speed tracking
  final Map<String, List<int>> _downloadSpeedTracker = {};
  final Map<String, DateTime> _downloadStartTime = {};

  // Retry tracking
  final Map<String, int> _retryCount = {};
  final Map<String, Timer> _retryTimers = {};
  final int _maxRetryAttempts = 5;

  // Dio instance for downloads
  final Dio _dio = Dio();

  VideoDownloadManager({
    required this.storageManager,
    required this.watermarkManager,
    required this.progressStreamController,
  });

  // Getters
  int get queuedItemsCount => _downloadQueue.length;
  int get activeDownloadsCount => _activeDownloads;

  set maxConcurrentDownloads(int value) {
    if (value > 0) {
      _maxConcurrentDownloads = value;
      _processQueue();
    }
  }

  Future<void> initialize() async {
    try {
      await _initializeDio();
      NyLogger.info('VideoDownloadManager initialized');
    } catch (e) {
      reportError('VideoDownloadManager.initialize', e);
    }
  }

  Future<void> _initializeDio() async {
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 600);
    _dio.options.headers = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
      'Accept': '*/*',
    };
  }

  void updateThrottling(bool enabled, int maxBytesPerSecond) {
    if (enabled) {
      _dio.interceptors.removeWhere((i) => i is ThrottlingInterceptor);
      _dio.interceptors.add(ThrottlingInterceptor(maxBytesPerSecond));
    } else {
      _dio.interceptors.removeWhere((i) => i is ThrottlingInterceptor);
    }
  }

  Future<bool> enqueueDownload({
    required String videoUrl,
    required String courseId,
    required String videoId,
    required String watermarkText,
    String email = "",
    required Course course,
    required List<dynamic> curriculum,
    int priority = 100,
    NetworkPreference networkPreference = NetworkPreference.any,
    double progress = 0.0,
    int retryCount = 0,
  }) async {
    try {
      String downloadKey = '${courseId}_${videoId}';

      // Check permissions
      bool hasPermission =
          await storageManager.checkAndRequestStoragePermissions();
      if (!hasPermission) {
        _notifyError(
            'permissionRequired',
            'Storage permission is required to download videos.',
            courseId,
            videoId);
        return false;
      }

      // Check if download is allowed
      DownloadPermission permission = await storageManager.canDownloadVideo(
        courseId: courseId,
        videoId: videoId,
      );

      if (!permission.isAllowed) {
        _notifyError('downloadBlocked', permission.reason, courseId, videoId);
        return false;
      }

      // Create and add queue item
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

      _downloadQueue.add(item);
      _sortQueue();

      // Initialize status
      _detailedStatus[downloadKey] = VideoDownloadStatus(
        phase: DownloadPhase.queued,
        progress: progress,
        message: "Queued for download",
        startTime: DateTime.now(),
        retryCount: retryCount,
        networkPreference: networkPreference,
      );

      _notifyProgressUpdate(courseId, videoId, progress,
          statusMessage: "Queued for download");
      await _saveQueueState();
      _processQueue();

      return true;
    } catch (e) {
      reportError('enqueueDownload', e);
      return false;
    }
  }

  Future<bool> downloadAllVideos({
    required String courseId,
    required Course course,
    required List<dynamic> curriculum,
    required String watermarkText,
    String email = "",
    NetworkPreference networkPreference = NetworkPreference.any,
  }) async {
    try {
      int successCount = 0;

      for (int i = 0; i < curriculum.length; i++) {
        var item = curriculum[i];

        if (!item.containsKey('video_url') || item['video_url'] == null) {
          continue;
        }

        String videoUrl = item['video_url'];
        String videoId = i.toString();

        bool isDownloaded = await storageManager.isVideoFullyDownloaded(
          videoUrl: videoUrl,
          courseId: courseId,
          videoId: videoId,
        );

        if (!isDownloaded &&
            !isDownloading(courseId, videoId) &&
            !isWatermarking(courseId, videoId) &&
            !isQueued(courseId, videoId)) {
          bool queued = await enqueueDownload(
            videoUrl: videoUrl,
            courseId: courseId,
            videoId: videoId,
            watermarkText: watermarkText,
            email: email,
            course: course,
            curriculum: curriculum,
            priority: 100 + i,
            networkPreference: networkPreference,
          );

          if (queued) successCount++;
        }
      }

      return successCount > 0;
    } catch (e) {
      reportError('downloadAllVideos', e);
      return false;
    }
  }

  void _sortQueue() {
    _downloadQueue.sort((a, b) {
      if (a.priority != b.priority) {
        return a.priority.compareTo(b.priority);
      }
      return a.queuedAt.compareTo(b.queuedAt);
    });
  }

  Future<void> _processQueue() async {
    if (_isProcessingQueue || _downloadQueue.isEmpty) return;

    _isProcessingQueue = true;

    try {
      // Check disk space
      bool hasEnoughSpace = await storageManager.checkDiskSpace();
      if (!hasEnoughSpace) {
        _notifyError('diskSpace',
            'Not enough disk space to continue downloads.', '', '');
        _isProcessingQueue = false;
        return;
      }

      // Process eligible items
      List<int> eligibleItemIndices = [];
      for (int i = 0; i < _downloadQueue.length; i++) {
        DownloadQueueItem item = _downloadQueue[i];
        if (!item.isPaused &&
            _canDownloadOnCurrentNetwork(item.networkPreference)) {
          eligibleItemIndices.add(i);
        }
      }

      // Start downloads up to max concurrent limit
      while (eligibleItemIndices.isNotEmpty &&
          _activeDownloads < _maxConcurrentDownloads) {
        int itemIndex = eligibleItemIndices.removeAt(0);
        DownloadQueueItem item = _downloadQueue.removeAt(itemIndex);

        // Adjust remaining indices
        for (int i = 0; i < eligibleItemIndices.length; i++) {
          if (eligibleItemIndices[i] > itemIndex) {
            eligibleItemIndices[i]--;
          }
        }

        _activeDownloads++;

        // Save download info
        await storageManager.saveDownloadInfo(
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

        // Start download process
        _startDownloadProcess(item);
      }

      await _saveQueueState();
    } catch (e) {
      reportError('processQueue', e);
    } finally {
      _isProcessingQueue = false;
    }
  }

  bool _canDownloadOnCurrentNetwork(NetworkPreference preference) {
    // This would be called from the main service with current connectivity
    // For now, assume any network is okay
    return true;
  }

  Future<void> _startDownloadProcess(DownloadQueueItem item) async {
    String downloadKey = '${item.courseId}_${item.videoId}';
    _retryCount[downloadKey] = item.retryCount;

    try {
      // Update status
      _downloadingStatus[downloadKey] = true;
      _watermarkingStatus[downloadKey] = false;
      _downloadProgress[downloadKey] = item.progress;
      _cancelRequests[downloadKey] = false;
      _downloadStartTime[downloadKey] = DateTime.now();
      _downloadSpeedTracker[downloadKey] = [];

      _detailedStatus[downloadKey] = VideoDownloadStatus(
        phase: DownloadPhase.initializing,
        progress: item.progress,
        message: "Preparing download...",
        startTime: DateTime.now(),
        retryCount: item.retryCount,
        networkPreference: item.networkPreference,
      );

      _notifyProgressUpdate(item.courseId, item.videoId, item.progress,
          statusMessage: "Preparing download...");

      // Step 1: Download video
      bool downloadSuccess = await _downloadVideo(
        videoUrl: item.videoUrl,
        courseId: item.courseId,
        videoId: item.videoId,
        resumeFromProgress: item.progress,
        onProgress: (progress, statusMessage) {
          if (_cancelRequests[downloadKey] == true) {
            throw CancelException("Download cancelled");
          }
          _notifyProgressUpdate(item.courseId, item.videoId, progress,
              statusMessage: statusMessage);

          // Update progress in storage
          _saveProgressToStorage(downloadKey, progress);
        },
      );

      if (!downloadSuccess) {
        throw Exception("Failed to download video");
      }

      // Step 2: Apply watermark
      if (downloadSuccess && _cancelRequests[downloadKey] != true) {
        _downloadingStatus[downloadKey] = false;
        _watermarkingStatus[downloadKey] = true;
        _watermarkProgress[downloadKey] = 0.0;

        _detailedStatus[downloadKey] = VideoDownloadStatus(
          phase: DownloadPhase.watermarking,
          progress: 0.0,
          message: "Adding watermark...",
          startTime: _detailedStatus[downloadKey]!.startTime,
          retryCount: item.retryCount,
          networkPreference: item.networkPreference,
        );

        _notifyProgressUpdate(item.courseId, item.videoId, 0.0,
            statusMessage: "Adding watermark...");

        bool watermarkSuccess = await watermarkManager.applyWatermark(
          courseId: item.courseId,
          videoId: item.videoId,
          watermarkText: item.watermarkText,
          email: item.email,
          onProgress: (progress) {
            if (_cancelRequests[downloadKey] == true) {
              throw CancelException("Watermarking cancelled");
            }
            _watermarkProgress[downloadKey] = progress;
            _notifyProgressUpdate(item.courseId, item.videoId, progress,
                statusMessage: "Adding watermark...");
          },
        );

        if (!watermarkSuccess) {
          throw Exception("Failed to apply watermark");
        }
      }

      // Handle successful completion
      await _handleDownloadComplete(
        courseId: item.courseId,
        videoId: item.videoId,
        success: true,
        course: item.course,
        curriculum: item.curriculum,
      );
    } catch (e) {
      await _handleDownloadError(item, e);
    } finally {
      _activeDownloads--;
      _processQueue();
    }
  }

  Future<bool> _downloadVideo({
    required String videoUrl,
    required String courseId,
    required String videoId,
    required Function(double, String) onProgress,
    double resumeFromProgress = 0.0,
  }) async {
    try {
      String downloadKey = '${courseId}_${videoId}';
      String outputPath =
          await storageManager.getVideoFilePath(courseId, videoId);

      // Setup for resuming
      File outputFile = File(outputPath);
      int startByte = 0;
      if (resumeFromProgress > 0 && await outputFile.exists()) {
        startByte = await outputFile.length();
      }

      Map<String, String> headers = {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Accept': '*/*',
      };

      if (startByte > 0) {
        headers['Range'] = 'bytes=$startByte-';
      }

      _detailedStatus[downloadKey] = VideoDownloadStatus(
        phase: DownloadPhase.downloading,
        progress: resumeFromProgress,
        message: "Downloading video...",
        startTime: _detailedStatus[downloadKey]!.startTime,
      );

      // Setup cancellation check
      Timer? cancelCheckTimer =
          Timer.periodic(Duration(milliseconds: 500), (timer) {
        if (_cancelRequests[downloadKey] == true) {
          _dio.close(force: true);
          timer.cancel();
        }
      });

      try {
        await _dio.download(
          videoUrl,
          outputPath,
          onReceiveProgress: (received, total) {
            if (_cancelRequests[downloadKey] == true) {
              throw CancelException("Download cancelled by user");
            }

            int adjustedReceived = received + startByte;
            int adjustedTotal = (total != -1) ? total + startByte : -1;

            if (adjustedTotal != -1) {
              double progress = adjustedReceived / adjustedTotal;

              // Update speed tracking
              _updateSpeedTracking(downloadKey, adjustedReceived);

              _detailedStatus[downloadKey] = VideoDownloadStatus(
                phase: DownloadPhase.downloading,
                progress: progress,
                message: "Downloading...",
                bytesReceived: adjustedReceived,
                totalBytes: adjustedTotal,
                startTime: _detailedStatus[downloadKey]!.startTime,
              );

              String speedInfo = getDownloadSpeed(courseId, videoId);
              onProgress(progress, "Downloading... • $speedInfo");
            }
          },
          options: Options(headers: headers),
        );

        cancelCheckTimer?.cancel();

        // Verify download
        if (!await outputFile.exists()) {
          return false;
        }

        int fileSize = await outputFile.length();
        if (fileSize < 1000) {
          return false;
        }

        return true;
      } catch (e) {
        cancelCheckTimer?.cancel();
        if (e is CancelException) {
          throw e;
        }
        // Try fallback method
        return await _fallbackDownload(
            videoUrl, outputPath, headers, onProgress);
      }
    } catch (e) {
      if (e is CancelException) {
        throw e;
      }
      return false;
    }
  }

  Future<bool> _fallbackDownload(String videoUrl, String outputPath,
      Map<String, String> headers, Function(double, String) onProgress) async {
    try {
      final httpClient = http.Client();
      final request = http.Request('GET', Uri.parse(videoUrl));
      request.headers.addAll(headers);

      final response = await httpClient.send(request);
      if (response.statusCode != 200 && response.statusCode != 206) {
        httpClient.close();
        return false;
      }

      final file = File(outputPath);
      final fileStream = file.openWrite();

      int received = 0;
      int total = response.contentLength ?? -1;

      await for (var chunk in response.stream) {
        fileStream.add(chunk);
        received += chunk.length;

        if (total != -1) {
          double progress = received / total;
          onProgress(progress, "Downloading with alternative method...");
        }
      }

      await fileStream.close();
      httpClient.close();
      return true;
    } catch (e) {
      return false;
    }
  }

  void _updateSpeedTracking(String downloadKey, int bytesReceived) {
    DateTime now = DateTime.now();
    DateTime? lastCheck = _downloadStartTime[downloadKey];

    if (lastCheck != null && now.difference(lastCheck).inSeconds >= 1) {
      _downloadSpeedTracker[downloadKey] ??= [];
      _downloadSpeedTracker[downloadKey]!.add(bytesReceived);

      if (_downloadSpeedTracker[downloadKey]!.length > 10) {
        _downloadSpeedTracker[downloadKey]!.removeAt(0);
      }

      _downloadStartTime[downloadKey] = now;
    }
  }

  Future<void> _handleDownloadError(
      DownloadQueueItem item, dynamic error) async {
    String downloadKey = '${item.courseId}_${item.videoId}';

    if (_cancelRequests[downloadKey] == true) {
      _detailedStatus[downloadKey] = VideoDownloadStatus(
        phase: DownloadPhase.cancelled,
        progress: 0.0,
        message: "Download cancelled",
      );
      _downloadingStatus[downloadKey] = false;
      _watermarkingStatus[downloadKey] = false;
      _notifyProgressUpdate(item.courseId, item.videoId, 0.0,
          statusMessage: "Download cancelled");
      await storageManager.removeFromPendingDownloads(
          item.courseId, item.videoId);
      return;
    }

    int currentRetryCount = _retryCount[downloadKey] ?? 0;

    if (currentRetryCount < _maxRetryAttempts) {
      int delaySeconds = _calculateRetryDelay(currentRetryCount);
      DateTime nextRetryTime =
          DateTime.now().add(Duration(seconds: delaySeconds));

      _retryCount[downloadKey] = currentRetryCount + 1;

      _detailedStatus[downloadKey] = VideoDownloadStatus(
        phase: DownloadPhase.error,
        progress: item.progress,
        message: "Download failed - will retry",
        error: error.toString(),
        retryCount: currentRetryCount,
        nextRetryTime: nextRetryTime,
        networkPreference: item.networkPreference,
      );

      _notifyProgressUpdate(item.courseId, item.videoId, item.progress,
          statusMessage: "Failed - retrying in ${delaySeconds}s");

      // Schedule retry
      _retryTimers[downloadKey] = Timer(Duration(seconds: delaySeconds), () {
        enqueueDownload(
          videoUrl: item.videoUrl,
          courseId: item.courseId,
          videoId: item.videoId,
          watermarkText: item.watermarkText,
          email: item.email,
          course: item.course,
          curriculum: item.curriculum,
          priority: 20,
          retryCount: currentRetryCount + 1,
          networkPreference: item.networkPreference,
          progress: item.progress,
        );
      });
    } else {
      _detailedStatus[downloadKey] = VideoDownloadStatus(
        phase: DownloadPhase.error,
        progress: 0.0,
        message: "Download failed after ${_retryCount[downloadKey]} retries",
        error: error.toString(),
      );

      _downloadingStatus[downloadKey] = false;
      _watermarkingStatus[downloadKey] = false;
      _notifyProgressUpdate(item.courseId, item.videoId, 0.0,
          statusMessage: "Download failed");
      await storageManager.removeFromPendingDownloads(
          item.courseId, item.videoId);
    }
  }

  int _calculateRetryDelay(int retryCount) {
    return (5 * pow(2, retryCount)).round();
  }

  Future<void> _handleDownloadComplete({
    required String courseId,
    required String videoId,
    required bool success,
    required Course course,
    required List<dynamic> curriculum,
  }) async {
    String downloadKey = '${courseId}_${videoId}';

    _downloadingStatus[downloadKey] = false;
    _watermarkingStatus[downloadKey] = false;

    if (_retryTimers.containsKey(downloadKey)) {
      _retryTimers[downloadKey]?.cancel();
      _retryTimers.remove(downloadKey);
    }

    if (success) {
      _downloadProgress[downloadKey] = 1.0;
      _watermarkProgress[downloadKey] = 1.0;
      _saveProgressToStorage(downloadKey, 1.0);

      _detailedStatus[downloadKey] = VideoDownloadStatus(
        phase: DownloadPhase.completed,
        progress: 1.0,
        message: "Download completed",
        startTime: _detailedStatus[downloadKey]?.startTime,
      );

      // Save metadata
      await storageManager.saveVideoMetadata(
        courseId: courseId,
        videoId: videoId,
        fileSize: await _getFileSize(courseId, videoId),
        watermarkText: await _getUserName(),
        isWatermarked: true,
      );
    } else {
      _detailedStatus[downloadKey] = VideoDownloadStatus(
        phase: DownloadPhase.error,
        progress: 0.0,
        message: "Download failed",
        startTime: _detailedStatus[downloadKey]?.startTime,
      );
    }

    await storageManager.removeFromPendingDownloads(courseId, videoId);
    _notifyProgressUpdate(courseId, videoId, success ? 1.0 : 0.0,
        statusMessage: _detailedStatus[downloadKey]!.displayMessage);
  }

  Future<int> _getFileSize(String courseId, String videoId) async {
    try {
      String path = await storageManager.getVideoFilePath(courseId, videoId);
      File file = File(path);
      return await file.exists() ? await file.length() : 0;
    } catch (e) {
      return 0;
    }
  }

  Future<String> _getUserName() async {
    try {
      var user = await Auth.data();
      return user?["full_name"] ?? "User";
    } catch (e) {
      return "User";
    }
  }

  void _saveProgressToStorage(String downloadKey, double progress) {
    try {
      NyStorage.save('progress_$downloadKey', progress);
    } catch (e) {
      // Ignore storage errors
    }
  }

  // Status checking methods
  double getProgress(String courseId, String videoId) {
    String key = '${courseId}_${videoId}';
    if (_watermarkingStatus[key] == true) {
      return _watermarkProgress[key] ?? 0.0;
    }
    return _downloadProgress[key] ?? 0.0;
  }

  bool isDownloading(String courseId, String videoId) {
    String key = '${courseId}_${videoId}';
    return _downloadingStatus[key] ?? false;
  }

  bool isWatermarking(String courseId, String videoId) {
    String key = '${courseId}_${videoId}';
    return _watermarkingStatus[key] ?? false;
  }

  bool isQueued(String courseId, String videoId) {
    return _downloadQueue
        .any((item) => item.courseId == courseId && item.videoId == videoId);
  }

  bool isPaused(String courseId, String videoId) {
    int index = _downloadQueue.indexWhere(
        (item) => item.courseId == courseId && item.videoId == videoId);
    return index >= 0 ? _downloadQueue[index].isPaused : false;
  }

  String getDownloadSpeed(String courseId, String videoId) {
    String key = '${courseId}_${videoId}';
    List<int> speedHistory = _downloadSpeedTracker[key] ?? [];
    if (speedHistory.isEmpty) return "0 KB/s";

    int recentMeasurements = speedHistory.length > 5 ? 5 : speedHistory.length;
    double avgSpeed = speedHistory
            .skip(speedHistory.length - recentMeasurements)
            .reduce((a, b) => a + b) /
        recentMeasurements;

    return _formatSpeed(avgSpeed.toInt());
  }

  String getEstimatedTimeRemaining(String courseId, String videoId) {
    String key = '${courseId}_${videoId}';
    VideoDownloadStatus status = _detailedStatus[key] ?? VideoDownloadStatus();

    if (status.isDownloading &&
        status.bytesReceived != null &&
        status.totalBytes != null &&
        _downloadSpeedTracker[key] != null &&
        _downloadSpeedTracker[key]!.isNotEmpty) {
      List<int> speedHistory = _downloadSpeedTracker[key]!;
      int recentMeasurements =
          speedHistory.length > 5 ? 5 : speedHistory.length;
      double avgSpeed = speedHistory
              .skip(speedHistory.length - recentMeasurements)
              .reduce((a, b) => a + b) /
          recentMeasurements;

      if (avgSpeed <= 0) return "";

      int remainingBytes = status.totalBytes! - status.bytesReceived!;
      int secondsRemaining = (remainingBytes / avgSpeed).round();

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

    return "";
  }

  String _formatSpeed(int bytesPerSecond) {
    if (bytesPerSecond < 1024) return "$bytesPerSecond B/s";
    if (bytesPerSecond < 1024 * 1024) {
      return "${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s";
    }
    return "${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s";
  }

  VideoDownloadStatus getDetailedStatus(String courseId, String videoId) {
    String key = '${courseId}_${videoId}';
    return _detailedStatus[key] ?? VideoDownloadStatus();
  }

  // Queue management
  Future<bool> pauseDownload(
      {required String courseId, required String videoId}) async {
    try {
      String downloadKey = '${courseId}_${videoId}';

      int index = _downloadQueue.indexWhere(
          (item) => item.courseId == courseId && item.videoId == videoId);

      if (index >= 0) {
        _downloadQueue[index].isPaused = true;
        _downloadQueue[index].pausedAt = DateTime.now();

        _detailedStatus[downloadKey] = VideoDownloadStatus(
          phase: DownloadPhase.paused,
          progress: _downloadQueue[index].progress,
          message: "Download paused",
        );

        _notifyProgressUpdate(courseId, videoId, _downloadQueue[index].progress,
            statusMessage: "Download paused");
        await _saveQueueState();
        return true;
      }

      if (_downloadingStatus[downloadKey] == true) {
        _cancelRequests[downloadKey] = true;
        _downloadingStatus[downloadKey] = false;
        return true;
      }

      return false;
    } catch (e) {
      reportError('pauseDownload', e);
      return false;
    }
  }

  Future<bool> resumeDownload(
      {required String courseId, required String videoId}) async {
    try {
      int index = _downloadQueue.indexWhere((item) =>
          item.courseId == courseId &&
          item.videoId == videoId &&
          item.isPaused);

      if (index >= 0) {
        _downloadQueue[index].isPaused = false;
        _downloadQueue[index].pausedAt = null;

        String downloadKey = '${courseId}_${videoId}';
        _detailedStatus[downloadKey] = VideoDownloadStatus(
          phase: DownloadPhase.queued,
          progress: _downloadQueue[index].progress,
          message: "Queued for download",
          retryCount: _downloadQueue[index].retryCount,
        );

        _notifyProgressUpdate(courseId, videoId, _downloadQueue[index].progress,
            statusMessage: "Queued for download");
        await _saveQueueState();
        _processQueue();
        return true;
      }

      return false;
    } catch (e) {
      reportError('resumeDownload', e);
      return false;
    }
  }

  Future<bool> cancelDownload(
      {required String courseId, required String videoId}) async {
    try {
      String key = '${courseId}_${videoId}';

      if (_downloadingStatus[key] == true || _watermarkingStatus[key] == true) {
        _cancelRequests[key] = true;
        _downloadingStatus[key] = false;
        _watermarkingStatus[key] = false;

        _detailedStatus[key] = VideoDownloadStatus(
          phase: DownloadPhase.cancelled,
          progress: _downloadProgress[key] ?? 0.0,
          message: "Download cancelled",
        );

        _notifyProgressUpdate(courseId, videoId, 0.0,
            statusMessage: "Download cancelled");
        _cleanupDownloadResources(courseId, videoId);
      }

      int index = _downloadQueue.indexWhere(
          (item) => item.courseId == courseId && item.videoId == videoId);

      if (index >= 0) {
        _downloadQueue.removeAt(index);
        await _saveQueueState();
      }

      await storageManager.removeFromPendingDownloads(courseId, videoId);
      return true;
    } catch (e) {
      reportError('cancelDownload', e);
      return false;
    }
  }

  Future<bool> prioritizeDownload(
      {required String courseId, required String videoId}) async {
    try {
      int index = _downloadQueue.indexWhere(
          (item) => item.courseId == courseId && item.videoId == videoId);

      if (index >= 0) {
        _downloadQueue[index].priority = 1;
        _sortQueue();
        await _saveQueueState();
        return true;
      }
      return false;
    } catch (e) {
      reportError('prioritizeDownload', e);
      return false;
    }
  }

  void _cleanupDownloadResources(String courseId, String videoId) {
    String downloadKey = '${courseId}_${videoId}';
    _downloadSpeedTracker.remove(downloadKey);
    _downloadStartTime.remove(downloadKey);
    _downloadingStatus[downloadKey] = false;
    _watermarkingStatus[downloadKey] = false;
    _cancelRequests[downloadKey] = false;

    if (_retryTimers.containsKey(downloadKey)) {
      _retryTimers[downloadKey]?.cancel();
      _retryTimers.remove(downloadKey);
    }
  }

  void handleNetworkChange(ConnectivityResult? connectivity, bool shouldPause) {
    if (shouldPause) {
      for (String key in _downloadingStatus.keys) {
        if (_downloadingStatus[key] == true) {
          _cancelRequests[key] = true;
        }
      }
    }
    _processQueue();
  }

  Future<int> cleanupStaleDownloads({required String courseId}) async {
    int cleanedCount = 0;
    try {
      final now = DateTime.now();
      List<String> keysToCleanup = [];

      for (var key in _downloadingStatus.keys) {
        if (_downloadingStatus[key] == true) {
          List<String> parts = key.split('_');
          if (parts.length == 2 && parts[0] == courseId) {
            DateTime? startTime = _downloadStartTime[key];
            if (startTime != null && now.difference(startTime).inMinutes > 30) {
              keysToCleanup.add(key);
            }
          }
        }
      }

      for (String key in keysToCleanup) {
        List<String> parts = key.split('_');
        if (parts.length == 2) {
          String courseId = parts[0];
          String videoId = parts[1];

          await cancelDownload(courseId: courseId, videoId: videoId);
          cleanedCount++;
        }
      }

      return cleanedCount;
    } catch (e) {
      reportError('cleanupStaleDownloads', e);
      return 0;
    }
  }

  Future<void> restoreState() async {
    try {
      await _restoreQueueState();
      await _restorePendingDownloads();
    } catch (e) {
      reportError('restoreState', e);
    }
  }

  Future<void> _restoreQueueState() async {
    try {
      String userSpecificKey =
          await storageManager.getUserSpecificKey('download_queue');
      String? queueDataString = await NyStorage.read(userSpecificKey);

      if (queueDataString != null && queueDataString.isNotEmpty) {
        List<dynamic> queueJson = jsonDecode(queueDataString);

        for (var itemJson in queueJson) {
          try {
            DownloadQueueItem item = DownloadQueueItem.fromJson(itemJson);
            _downloadQueue.add(item);

            String downloadKey = '${item.courseId}_${item.videoId}';
            _downloadProgress[downloadKey] = item.progress;
            _downloadingStatus[downloadKey] = false;
            _cancelRequests[downloadKey] = false;
            _watermarkingStatus[downloadKey] = false;

            _detailedStatus[downloadKey] = VideoDownloadStatus(
              phase:
                  item.isPaused ? DownloadPhase.paused : DownloadPhase.queued,
              progress: item.progress,
              message:
                  item.isPaused ? "Download paused" : "Queued for download",
              retryCount: item.retryCount,
              networkPreference: item.networkPreference,
            );
          } catch (e) {
            reportError('restore_queue_item', e);
          }
        }
      }
    } catch (e) {
      reportError('restoreQueueState', e);
    }
  }

  Future<void> _restorePendingDownloads() async {
    try {
      String userSpecificKey =
          await storageManager.getUserSpecificKey('pending_downloads');
      List<dynamic> pendingDownloads =
          await storageManager.getPendingDownloads();

      for (dynamic item in pendingDownloads) {
        try {
          Map<String, dynamic> downloadData =
              storageManager.parsePendingDownloadItem(item);
          if (downloadData.isEmpty) continue;

          await enqueueDownload(
            videoUrl: downloadData['videoUrl'],
            courseId: downloadData['courseId'],
            videoId: downloadData['videoId'],
            watermarkText: downloadData['watermarkText'] ?? '',
            email: downloadData['email'] ?? '',
            course: Course.fromJson(downloadData['course']),
            curriculum: downloadData['curriculum'] ?? [],
            priority: 10,
            progress: downloadData['progress'] ?? 0.0,
            retryCount: downloadData['retryCount'] ?? 0,
          );
        } catch (e) {
          reportError('restore_pending_download', e);
        }
      }
    } catch (e) {
      reportError('restorePendingDownloads', e);
    }
  }

  Future<void> _saveQueueState() async {
    try {
      List<Map<String, dynamic>> queueData =
          _downloadQueue.map((item) => item.toJson()).toList();
      String userSpecificKey =
          await storageManager.getUserSpecificKey('download_queue');
      await NyStorage.save(userSpecificKey, jsonEncode(queueData));
    } catch (e) {
      reportError('saveQueueState', e);
    }
  }

  void _notifyProgressUpdate(String courseId, String videoId, double progress,
      {String statusMessage = ""}) {
    String key = '${courseId}_${videoId}';
    bool isWatermarking = _watermarkingStatus[key] ?? false;

    progressStreamController.add({
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

  void _notifyError(
      String errorType, String message, String courseId, String videoId) {
    progressStreamController.add({
      'type': 'error',
      'errorType': errorType,
      'message': message,
      'courseId': courseId,
      'videoId': videoId,
    });
  }

  Future<void> handleUserLogout() async {
    try {
      // Cancel all active downloads
      for (var key in _downloadingStatus.keys) {
        if (_downloadingStatus[key] == true) {
          _cancelRequests[key] = true;
        }
      }

      await _saveQueueState();

      // Clear in-memory data
      _downloadQueue.clear();
      _downloadProgress.clear();
      _downloadingStatus.clear();
      _cancelRequests.clear();
      _watermarkingStatus.clear();
      _watermarkProgress.clear();
      _detailedStatus.clear();
    } catch (e) {
      reportError('handleUserLogout', e);
    }
  }

  void dispose() {
    try {
      _dio.close(force: true);
      for (var timer in _retryTimers.values) {
        timer.cancel();
      }
      _retryTimers.clear();
    } catch (e) {
      reportError('VideoDownloadManager.dispose', e);
    }
  }
}
