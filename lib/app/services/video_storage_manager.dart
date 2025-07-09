import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_app/app/models/course.dart';
import 'package:flutter_app/app/services/video_service_utils.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:storage_info/storage_info.dart';

class VideoStorageManager {
  static const int MIN_VIDEO_SIZE_KB = 100;
  static const int MIN_REQUIRED_SPACE_MB = 500;

  final Map<String, VideoDownloadMetadata> _videoMetadata = {};

  String? _currentUserId;
  bool _permissionsGranted = false;
  bool _isRequestingPermission = false;
  DateTime? _lastPermissionCheck;
  final Duration _permissionCacheTime = Duration(hours: 24);

  Future<void> initialize() async {
    try {
      await _setCurrentUserContext();
      NyLogger.info('VideoStorageManager initialized');
    } catch (e) {
      reportError('VideoStorageManager.initialize', e);
    }
  }

  Future<void> _setCurrentUserContext() async {
    try {
      var user = await Auth.data();
      if (user != null) {
        _currentUserId = user['id']?.toString();
      }
    } catch (e) {
      reportError('set_current_user_context', e);
      _currentUserId = null;
    }
  }

  String getUserSpecificKey(String baseKey) {
    if (_currentUserId != null && _currentUserId!.isNotEmpty) {
      return '${baseKey}_user_$_currentUserId';
    }
    return baseKey;
  }

  Future<String> getVideoFilePath(String courseId, String videoId) async {
    Directory appDir = await getApplicationDocumentsDirectory();
    String userId = _currentUserId ?? 'default_user';
    String userPath = '${appDir.path}/users/$userId/courses/$courseId/videos';
    await Directory(userPath).create(recursive: true);
    return '$userPath/video_$videoId.mp4';
  }

  Future<String> getWatermarkFlagPath(String courseId, String videoId) async {
    String videoPath = await getVideoFilePath(courseId, videoId);
    return '$videoPath.watermarked';
  }

  // Permission management
  Future<bool> checkAndRequestStoragePermissions() async {
    try {
      if (_isRequestingPermission) {
        int waitCount = 0;
        while (_isRequestingPermission && waitCount < 20) {
          await Future.delayed(Duration(milliseconds: 500));
          waitCount++;
        }
        return _permissionsGranted;
      }

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
          return hasPermission;
        } else if (Platform.isIOS) {
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
      reportError('checkAndRequestStoragePermissions', e,
          stackTrace: stackTrace);
      return false;
    }
  }

  Future<bool> _checkAndroidPermissions() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;

      if (androidInfo.version.sdkInt >= 33) {
        bool videosGranted = await Permission.videos.isGranted;
        bool audioGranted = await Permission.audio.isGranted;
        return videosGranted && audioGranted;
      } else {
        return await Permission.storage.isGranted;
      }
    } catch (e) {
      reportError('checkAndroidPermissions', e);
      return false;
    }
  }

  Future<bool> _requestAndroidPermissions() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;

      if (androidInfo.version.sdkInt >= 33) {
        Map<Permission, PermissionStatus> statuses = await [
          Permission.videos,
          Permission.audio,
        ].request();

        bool videosGranted = statuses[Permission.videos]?.isGranted ?? false;
        bool audioGranted = statuses[Permission.audio]?.isGranted ?? false;
        return videosGranted && audioGranted;
      } else {
        PermissionStatus status = await Permission.storage.request();
        return status.isGranted;
      }
    } catch (e) {
      reportError('requestAndroidPermissions', e);
      return false;
    }
  }

  // File operations
  Future<bool> isVideoFullyDownloaded({
    required String videoUrl,
    required String courseId,
    required String videoId,
  }) async {
    try {
      String videoPath = await getVideoFilePath(courseId, videoId);
      File videoFile = File(videoPath);

      if (!await videoFile.exists()) return false;

      int fileSize = await videoFile.length();
      if (fileSize < 1024 * 10) return false;

      bool isMarkedComplete =
          await _isDownloadMarkedComplete(courseId, videoId);
      if (!isMarkedComplete) return false;

      bool hasWatermarkFlag = await _hasWatermarkFlag(courseId, videoId);
      if (!hasWatermarkFlag) return false;

      return true;
    } catch (e) {
      reportError('isVideoFullyDownloaded', e);
      return false;
    }
  }

  Future<bool> _isDownloadMarkedComplete(
      String courseId, String videoId) async {
    try {
      String key = 'progress_${courseId}_$videoId';
      dynamic progress = await NyStorage.read(key);

      if (progress is double) {
        return progress >= 1.0;
      } else if (progress is int) {
        return progress >= 1;
      } else if (progress is String) {
        try {
          double progressValue = double.parse(progress);
          return progressValue >= 1.0;
        } catch (e) {
          return false;
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> _hasWatermarkFlag(String courseId, String videoId) async {
    try {
      String watermarkFlagPath = await getWatermarkFlagPath(courseId, videoId);
      File watermarkFlagFile = File(watermarkFlagPath);
      return await watermarkFlagFile.exists();
    } catch (e) {
      return false;
    }
  }

  Future<VideoStatus> getVideoStatus({
    required String courseId,
    required String videoId,
    required Function(String, String) isDownloading,
    required Function(String, String) isWatermarking,
    required Function(String, String) isQueued,
  }) async {
    try {
      String videoPath = await getVideoFilePath(courseId, videoId);
      File videoFile = File(videoPath);

      if (!await videoFile.exists()) {
        await _cleanupVideoMetadata(courseId, videoId);
        return VideoStatus.notDownloaded;
      }

      int fileSize = await videoFile.length();
      if (fileSize < MIN_VIDEO_SIZE_KB * 1024) {
        await _cleanupCorruptedVideo(courseId, videoId);
        return VideoStatus.corrupted;
      }

      if (isDownloading(courseId, videoId) ||
          isWatermarking(courseId, videoId) ||
          isQueued(courseId, videoId)) {
        return VideoStatus.processing;
      }

      VideoDownloadMetadata? metadata =
          await _loadVideoMetadata(courseId, videoId);
      if (metadata == null) {
        return VideoStatus.corrupted;
      }

      if ((metadata.fileSize - fileSize).abs() > 1024 * 1024) {
        await _cleanupCorruptedVideo(courseId, videoId);
        return VideoStatus.corrupted;
      }

      bool hasWatermarkFlag = await _hasWatermarkFlag(courseId, videoId);
      if (!hasWatermarkFlag) {
        return VideoStatus.corrupted;
      }

      return VideoStatus.downloaded;
    } catch (e) {
      reportError('getVideoStatus', e);
      return VideoStatus.unknown;
    }
  }

  Future<DownloadPermission> canDownloadVideo({
    required String courseId,
    required String videoId,
  }) async {
    try {
      VideoStatus status = await getVideoStatus(
        courseId: courseId,
        videoId: videoId,
        isDownloading: (c, v) =>
            false, // These will be passed from the download manager
        isWatermarking: (c, v) => false,
        isQueued: (c, v) => false,
      );

      switch (status) {
        case VideoStatus.notDownloaded:
          return DownloadPermission.allowed("Video not downloaded");
        case VideoStatus.corrupted:
          return DownloadPermission.allowed("Previous download was corrupted");
        case VideoStatus.processing:
          return DownloadPermission.blocked(
              "Download/processing already in progress");
        case VideoStatus.downloaded:
          return DownloadPermission.blocked(
              "Video already downloaded. Delete first to redownload.");
        case VideoStatus.unknown:
          return DownloadPermission.allowed(
              "Unable to verify status - allowing download");
      }
    } catch (e) {
      reportError('canDownloadVideo', e);
      return DownloadPermission.allowed(
          "Error checking status - allowing download");
    }
  }

  Future<bool> deleteVideo({
    required String courseId,
    required String videoId,
  }) async {
    try {
      String videoPath = await getVideoFilePath(courseId, videoId);
      File videoFile = File(videoPath);
      File watermarkFlagFile = File('$videoPath.watermarked');

      bool videoExists = await videoFile.exists();
      bool flagExists = await watermarkFlagFile.exists();

      if (!videoExists && !flagExists) {
        await _cleanupVideoMetadata(courseId, videoId);
        return true;
      }

      bool success = true;
      if (videoExists) {
        try {
          await videoFile.delete();
        } catch (e) {
          reportError('deleteVideoFile', e);
          success = false;
        }
      }

      if (flagExists) {
        try {
          await watermarkFlagFile.delete();
        } catch (e) {
          reportError('deleteWatermarkFlag', e);
        }
      }

      await _cleanupVideoMetadata(courseId, videoId);
      await _cleanupCacheFiles(courseId, videoId);

      return success;
    } catch (e) {
      reportError('deleteVideo', e);
      return false;
    }
  }

  Future<void> _cleanupCorruptedVideo(String courseId, String videoId) async {
    try {
      String videoPath = await getVideoFilePath(courseId, videoId);
      File videoFile = File(videoPath);
      File watermarkFlagFile = File('$videoPath.watermarked');

      if (await videoFile.exists()) {
        await videoFile.delete();
      }

      if (await watermarkFlagFile.exists()) {
        await watermarkFlagFile.delete();
      }

      await _cleanupVideoMetadata(courseId, videoId);
      await _cleanupCacheFiles(courseId, videoId);
    } catch (e) {
      reportError('cleanupCorruptedVideo', e);
    }
  }

  Future<void> _cleanupCacheFiles(String courseId, String videoId) async {
    try {
      Directory tempDir = await getTemporaryDirectory();
      List<String> potentialCacheFiles = [
        '${tempDir.path}/watermark_check_$videoId.jpg',
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
      reportError('cleanupCacheFiles', e);
    }
  }

  // Metadata management
  Future<void> saveVideoMetadata({
    required String courseId,
    required String videoId,
    required int fileSize,
    required String watermarkText,
    required bool isWatermarked,
    String? checksum,
  }) async {
    try {
      String calculatedChecksum =
          checksum ?? await _calculateFileChecksum(courseId, videoId);

      final metadata = VideoDownloadMetadata(
        courseId: courseId,
        videoId: videoId,
        downloadedAt: DateTime.now(),
        fileSize: fileSize,
        watermarkText: watermarkText,
        isWatermarked: isWatermarked,
        checksum: calculatedChecksum,
      );

      String key = getUserSpecificKey('video_metadata_${courseId}_${videoId}');
      await NyStorage.save(key, jsonEncode(metadata.toJson()));

      _videoMetadata['${courseId}_${videoId}'] = metadata;
    } catch (e) {
      reportError('saveVideoMetadata', e);
    }
  }

  Future<VideoDownloadMetadata?> _loadVideoMetadata(
      String courseId, String videoId) async {
    try {
      String downloadKey = '${courseId}_${videoId}';

      if (_videoMetadata.containsKey(downloadKey)) {
        return _videoMetadata[downloadKey];
      }

      String key = getUserSpecificKey('video_metadata_${courseId}_${videoId}');
      String? metadataString = await NyStorage.read(key);

      if (metadataString != null && metadataString.isNotEmpty) {
        Map<String, dynamic> metadataJson = jsonDecode(metadataString);
        VideoDownloadMetadata metadata =
            VideoDownloadMetadata.fromJson(metadataJson);
        _videoMetadata[downloadKey] = metadata;
        return metadata;
      }

      return null;
    } catch (e) {
      reportError('loadVideoMetadata', e);
      return null;
    }
  }

  Future<void> _cleanupVideoMetadata(String courseId, String videoId) async {
    try {
      String downloadKey = '${courseId}_${videoId}';
      _videoMetadata.remove(downloadKey);

      String key = getUserSpecificKey('video_metadata_${courseId}_${videoId}');
      await NyStorage.delete(key);
    } catch (e) {
      reportError('cleanupVideoMetadata', e);
    }
  }

  Future<String> _calculateFileChecksum(String courseId, String videoId) async {
    try {
      String videoPath = await getVideoFilePath(courseId, videoId);
      File file = File(videoPath);

      if (!await file.exists()) return 'unknown';

      int fileSize = await file.length();
      DateTime lastModified = await file.lastModified();
      return '${fileSize}_${lastModified.millisecondsSinceEpoch}';
    } catch (e) {
      return 'unknown';
    }
  }

  // Download info management
  Future<void> saveDownloadInfo({
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
        'userId': _currentUserId,
      };

      String downloadKey = '${courseId}_${videoId}';
      String progressKey = getUserSpecificKey('progress_$downloadKey');
      await NyStorage.save(progressKey, 0.0);

      String pendingKey = getUserSpecificKey('pending_downloads');
      List<dynamic> pendingDownloads = await getPendingDownloads();

      // Remove existing entry
      pendingDownloads.removeWhere((item) {
        try {
          Map<String, dynamic> data = parsePendingDownloadItem(item);
          return data['courseId'] == courseId && data['videoId'] == videoId;
        } catch (e) {
          return false;
        }
      });

      pendingDownloads.add(downloadInfo);
      await NyStorage.save(pendingKey, pendingDownloads);
    } catch (e) {
      reportError('saveDownloadInfo', e);
    }
  }

  Future<List<dynamic>> getPendingDownloads() async {
    try {
      String pendingKey = getUserSpecificKey('pending_downloads');
      dynamic existingData = await NyStorage.read(pendingKey);

      if (existingData is List) {
        return existingData;
      } else if (existingData is String) {
        try {
          var decoded = jsonDecode(existingData);
          if (decoded is List) {
            return decoded;
          }
        } catch (e) {
          // Invalid JSON, return empty list
        }
      }
      return [];
    } catch (e) {
      reportError('getPendingDownloads', e);
      return [];
    }
  }

  Map<String, dynamic> parsePendingDownloadItem(dynamic item) {
    try {
      if (item is String) {
        return jsonDecode(item);
      } else if (item is Map) {
        return Map<String, dynamic>.from(item);
      }
      return {};
    } catch (e) {
      return {};
    }
  }

  Future<void> removeFromPendingDownloads(
      String courseId, String videoId) async {
    try {
      String pendingKey = getUserSpecificKey('pending_downloads');
      List<dynamic> pendingDownloads = await getPendingDownloads();

      List<dynamic> updatedDownloads = pendingDownloads.where((item) {
        try {
          Map<String, dynamic> downloadData = parsePendingDownloadItem(item);
          return !(downloadData['courseId'] == courseId &&
              downloadData['videoId'] == videoId);
        } catch (e) {
          return true; // Keep items we can't parse
        }
      }).toList();

      await NyStorage.save(pendingKey, updatedDownloads);
    } catch (e) {
      reportError('removeFromPendingDownloads', e);
    }
  }

  // Disk space management
  Future<bool> checkDiskSpace() async {
    try {
      final storageInfoPlugin = StorageInfo();
      double? freeDiskSpace = await storageInfoPlugin.getStorageFreeSpace();

      if (freeDiskSpace != null) {
        double freeSpaceMB = freeDiskSpace;

        if (freeSpaceMB < MIN_REQUIRED_SPACE_MB) {
          NyLogger.error(
              'Not enough disk space: ${freeSpaceMB.toStringAsFixed(2)} MB available, required: $MIN_REQUIRED_SPACE_MB MB');
          return false;
        }
        return true;
      }

      // If we can't determine disk space, assume it's ok
      return true;
    } catch (e) {
      reportError('checkDiskSpace', e);
      return true; // Assume ok to avoid blocking downloads
    }
  }

  // User data management
  Future<void> cleanupOtherUsersData() async {
    try {
      String currentUserId = _currentUserId ?? 'default_user';
      await _cleanupOtherUsersStorageKeys(currentUserId);
    } catch (e) {
      reportError('cleanupOtherUsersData', e);
    }
  }

  Future<void> _cleanupOtherUsersStorageKeys(String currentUserId) async {
    try {
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

      for (String baseKey in knownUserKeys) {
        for (int i = 1; i <= 10; i++) {
          String otherUserKey = '${baseKey}_user_$i';
          if (otherUserKey != '${baseKey}_user_$currentUserId') {
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

      for (String key in keysToRemove) {
        try {
          await NyStorage.delete(key);
        } catch (e) {
          reportError('deleteOtherUserKey', e);
        }
      }
    } catch (e) {
      reportError('cleanupOtherUsersStorageKeys', e);
    }
  }

  // Utility methods
  Future<String> getVideoTitle(String courseId, String videoId) async {
    try {
      List<dynamic> pendingDownloads = await getPendingDownloads();

      for (dynamic item in pendingDownloads) {
        Map<String, dynamic> downloadData = parsePendingDownloadItem(item);
        if (downloadData.isEmpty) continue;

        if (downloadData['courseId'] == courseId) {
          String courseName = "";
          if (downloadData.containsKey('course')) {
            Course course = Course.fromJson(downloadData['course']);
            courseName = course.title;
          }

          List<dynamic> curriculum = downloadData['curriculum'] ?? [];

          try {
            int videoIndex = int.parse(videoId);
            if (videoIndex >= 0 && videoIndex < curriculum.length) {
              String videoTitle =
                  curriculum[videoIndex]['title'] ?? "Video $videoId";
              return courseName.isNotEmpty
                  ? "$courseName - $videoTitle"
                  : videoTitle;
            }
          } catch (e) {
            // Try looking for video_id match
            for (var lecture in curriculum) {
              if (lecture is Map &&
                  lecture.containsKey('video_id') &&
                  lecture['video_id'].toString() == videoId) {
                String videoTitle = lecture['title'] ?? "Video $videoId";
                return courseName.isNotEmpty
                    ? "$courseName - $videoTitle"
                    : videoTitle;
              }
            }
          }
        }
      }

      return "Video $videoId";
    } catch (e) {
      reportError('getVideoTitle', e);
      return "Video $videoId";
    }
  }

  void dispose() {
    try {
      _videoMetadata.clear();
      NyLogger.info('VideoStorageManager disposed');
    } catch (e) {
      reportError('VideoStorageManager.dispose', e);
    }
  }
}
