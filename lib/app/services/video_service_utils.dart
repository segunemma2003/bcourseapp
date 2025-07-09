import 'dart:async';
import 'dart:typed_data';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:nylo_framework/nylo_framework.dart';
// Import required for math operations
import 'dart:math' as math;

// Missing imports that are needed
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_app/app/models/course.dart';

// Error reporting utility
void reportError(String operation, dynamic error,
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

// Get current user ID utility
Future<String> getCurrentUserId() async {
  try {
    var user = await Auth.data();
    if (user != null && user['id'] != null) {
      return user['id'].toString();
    }
  } catch (e) {
    reportError('get_current_user_id', e);
  }
  return 'default_user'; // Fallback
}

// Enums
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

enum VideoStatus {
  notDownloaded, // Video has not been downloaded yet
  corrupted, // Video was downloaded but is corrupted/incomplete
  processing, // Video is currently being downloaded/watermarked/queued
  downloaded, // Video is fully downloaded and valid
  unknown, // Unable to determine status (error state)
}

// Extensions
extension VideoStatusExtension on VideoStatus {
  bool get canDownload =>
      this == VideoStatus.notDownloaded || this == VideoStatus.corrupted;
  bool get canPlay => this == VideoStatus.downloaded;
  bool get isProcessing => this == VideoStatus.processing;
  bool get needsRedownload => this == VideoStatus.corrupted;

  String get displayText {
    switch (this) {
      case VideoStatus.notDownloaded:
        return "Not Downloaded";
      case VideoStatus.corrupted:
        return "Corrupted";
      case VideoStatus.processing:
        return "Processing";
      case VideoStatus.downloaded:
        return "Downloaded";
      case VideoStatus.unknown:
        return "Unknown";
    }
  }
}

// Exception classes
class CancelException implements Exception {
  final String message;
  CancelException(this.message);
}

class PauseException implements Exception {
  final String message;
  PauseException(this.message);
}

// Permission classes
class DownloadPermission {
  final bool isAllowed;
  final String reason;

  DownloadPermission.allowed(this.reason) : isAllowed = true;
  DownloadPermission.blocked(this.reason) : isAllowed = false;
}

// Status classes
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

// Throttling interceptor for Dio
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

// Queue item class
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

  // Enhanced functionality fields
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
      queuedAt: json['queuedAt'] != null
          ? DateTime.parse(json['queuedAt'])
          : DateTime.now(),
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

// Utility functions for URL validation
bool isLikelyVideoUrl(String url) {
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

// Format speed utility
String formatSpeed(int bytesPerSecond) {
  if (bytesPerSecond < 1024) return "$bytesPerSecond B/s";
  if (bytesPerSecond < 1024 * 1024) {
    return "${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s";
  }
  return "${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s";
}

// Format bytes utility
String formatBytes(int bytes) {
  if (bytes < 1024) return "$bytes B";
  if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
  return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
}

// Format time utility
String formatTime(int seconds) {
  if (seconds < 60) {
    return "$seconds seconds";
  } else if (seconds < 3600) {
    int minutes = seconds ~/ 60;
    return "$minutes minutes";
  } else {
    int hours = seconds ~/ 3600;
    int minutes = (seconds % 3600) ~/ 60;
    return "$hours hours, $minutes minutes";
  }
}

// Validation utilities
bool isValidVideoUrl(String url) {
  try {
    Uri uri = Uri.parse(url);
    return uri.isAbsolute && isLikelyVideoUrl(url);
  } catch (e) {
    return false;
  }
}

bool isValidEmail(String email) {
  return RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
      .hasMatch(email);
}

// Network utility functions
bool canDownloadOnNetwork(
    NetworkPreference preference, ConnectivityResult? connectivity) {
  if (preference == NetworkPreference.any) {
    return connectivity != ConnectivityResult.none;
  }

  if (preference == NetworkPreference.wifiAndMobile) {
    return connectivity == ConnectivityResult.wifi ||
        connectivity == ConnectivityResult.mobile;
  }

  if (preference == NetworkPreference.wifiOnly) {
    return connectivity == ConnectivityResult.wifi;
  }

  return false;
}

// File size validation
bool isValidVideoFileSize(int fileSize) {
  const int minSizeBytes = 1024 * 100; // 100KB minimum
  const int maxSizeBytes = 1024 * 1024 * 1024 * 5; // 5GB maximum
  return fileSize >= minSizeBytes && fileSize <= maxSizeBytes;
}

// Retry delay calculation
int calculateRetryDelay(int retryCount, {int baseDelaySeconds = 5}) {
  return (baseDelaySeconds * math.pow(2, retryCount)).round();
}

class VideoDownloadMetadata {
  final String courseId;
  final String videoId;
  final DateTime downloadedAt;
  final int fileSize;
  final String watermarkText;
  final bool isWatermarked;
  final String checksum; // For integrity verification

  VideoDownloadMetadata({
    required this.courseId,
    required this.videoId,
    required this.downloadedAt,
    required this.fileSize,
    required this.watermarkText,
    required this.isWatermarked,
    required this.checksum,
  });

  Map<String, dynamic> toJson() {
    return {
      'courseId': courseId,
      'videoId': videoId,
      'downloadedAt': downloadedAt.toIso8601String(),
      'fileSize': fileSize,
      'watermarkText': watermarkText,
      'isWatermarked': isWatermarked,
      'checksum': checksum,
    };
  }

  factory VideoDownloadMetadata.fromJson(Map<String, dynamic> json) {
    return VideoDownloadMetadata(
      courseId: json['courseId'],
      videoId: json['videoId'],
      downloadedAt: DateTime.parse(json['downloadedAt']),
      fileSize: json['fileSize'],
      watermarkText: json['watermarkText'] ?? '',
      isWatermarked: json['isWatermarked'] ?? false,
      checksum: json['checksum'] ?? '',
    );
  }
}
