import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:isolate';
import 'dart:async'; // Add this import for StreamController
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:ffmpeg_kit_flutter_new/log.dart';
import 'package:ffmpeg_kit_flutter_new/statistics.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:dio/dio.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as path;
import 'package:flutter_isolate/flutter_isolate.dart';

import '../../resources/pages/video_player_page.dart';
import '../../app/models/course.dart';

// Regular class for VideoService
class VideoService {
  // Singleton instance
  static final VideoService _instance = VideoService._internal();

  factory VideoService() {
    return _instance;
  }

  VideoService._internal();

  // Dio instance for download with progress
  final Dio _dio = Dio();

  // Map to store progress and download status
  final Map<String, double> _downloadProgress = {};
  final Map<String, bool> _downloadingStatus = {};

  // Stream controller for download progress updates
  final StreamController<Map<String, dynamic>> _progressStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  // Getter for progress stream
  Stream<Map<String, dynamic>> get progressStream =>
      _progressStreamController.stream;

  // Initialize service - call this in Boot.finished
  Future<void> initialize() async {
    // Check for any previously pending downloads
    await _restorePendingDownloads();

    // Log service initialization
    NyLogger.info('[VideoService] Initialized successfully');
  }

  // Check and restore any pending downloads from previous app sessions
  Future<void> _restorePendingDownloads() async {
    try {
      // Get pending downloads from NyStorage - handle possible String/List type issues
      dynamic pendingDownloadsRaw = await NyStorage.read('pending_downloads');
      List<dynamic> pendingDownloads = [];

      if (pendingDownloadsRaw is List) {
        pendingDownloads = pendingDownloadsRaw;
      } else if (pendingDownloadsRaw is String) {
        try {
          // Try to parse if it's a JSON string
          var decoded = jsonDecode(pendingDownloadsRaw);
          if (decoded is List) {
            pendingDownloads = decoded;
          }
        } catch (e) {
          // If parsing fails, start with empty list
          pendingDownloads = [];
        }
      }

      if (pendingDownloads.isNotEmpty) {
        for (dynamic item in pendingDownloads) {
          try {
            // Parse pending download data
            Map<String, dynamic> downloadData;
            if (item is String) {
              downloadData = jsonDecode(item);
            } else if (item is Map) {
              downloadData = Map<String, dynamic>.from(item);
            } else {
              continue; // Skip invalid items
            }

            // Mark as in progress for UI to show
            String videoId = downloadData['videoId'];
            String courseId = downloadData['courseId'];
            String downloadKey = '${courseId}_${videoId}';

            _downloadingStatus[downloadKey] = true;

            // Get progress, handling potential type issues
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

            _downloadProgress[downloadKey] = progress;

            // Notify listeners
            _notifyProgressUpdate(
                courseId, videoId, _downloadProgress[downloadKey] ?? 0.0);

            // Continue download in background if needed
            if (downloadData.containsKey('videoUrl') &&
                downloadData.containsKey('courseId') &&
                downloadData.containsKey('videoId') &&
                downloadData.containsKey('watermarkText')) {
              // Get course and curriculum data, with fallbacks
              dynamic course = downloadData['course'];
              List<dynamic> curriculum = [];
              if (downloadData.containsKey('curriculum')) {
                dynamic curriculumData = downloadData['curriculum'];
                if (curriculumData is List) {
                  curriculum = curriculumData;
                }
              }

              // Start download process in background
              _startIsolatedDownload(
                videoUrl: downloadData['videoUrl'],
                courseId: downloadData['courseId'],
                videoId: downloadData['videoId'],
                watermarkText: downloadData['watermarkText'],
                course: course,
                curriculum: curriculum,
              );
            }
          } catch (e) {
            NyLogger.error('[VideoService] Error restoring download: $e');
          }
        }
      }
    } catch (e) {
      NyLogger.error('[VideoService] Error checking pending downloads: $e');
    }
  }

  // Method to get current progress for a download
  double getProgress(String courseId, String videoId) {
    String key = '${courseId}_${videoId}';
    return _downloadProgress[key] ?? 0.0;
  }

  // Method to check if a download is in progress
  bool isDownloading(String courseId, String videoId) {
    String key = '${courseId}_${videoId}';
    return _downloadingStatus[key] ?? false;
  }

  // Method to start download in background
  Future<bool> startBackgroundDownload({
    required String videoUrl,
    required String courseId,
    required String videoId,
    required String watermarkText,
    String email = "",
    required Course course,
    required List<dynamic> curriculum,
  }) async {
    try {
      // Check if download is already in progress
      String downloadKey = '${courseId}_${videoId}';
      if (_downloadingStatus[downloadKey] == true) {
        NyLogger.info('[VideoService] Download already in progress');
        return false;
      }

      // Mark as downloading
      _downloadingStatus[downloadKey] = true;
      _downloadProgress[downloadKey] = 0.0;

      // Save to NyStorage for persistence
      await _saveDownloadInfo(
        videoUrl: videoUrl,
        courseId: courseId,
        videoId: videoId,
        watermarkText: watermarkText,
        course: course,
        curriculum: curriculum,
      );

      // Notify about initial progress
      _notifyProgressUpdate(courseId, videoId, 0.0);

      // Log the download start
      NyLogger.info(
          '[VideoService] Download started for video $videoId in course $courseId');

      // Skip isolate approach for now and download directly
      try {
        bool success = await downloadVideo(
          videoUrl: videoUrl,
          courseId: courseId,
          videoId: videoId,
          watermarkText: watermarkText,
          email: email, // Pass email
          onProgress: (progress) {
            _notifyProgressUpdate(courseId, videoId, progress);
            NyStorage.save('progress_$downloadKey', progress);
          },
        );

        // Handle completion
        _handleDownloadComplete(
          courseId: courseId,
          videoId: videoId,
          success: success,
          course: course,
          curriculum: curriculum,
        );

        return success;
      } catch (e) {
        NyLogger.error('[VideoService] Download process error: $e');

        // Update status on error
        _downloadingStatus[downloadKey] = false;
        _notifyProgressUpdate(courseId, videoId, 0.0);

        // Remove from pending downloads
        await _removeFromPendingDownloads(courseId, videoId);

        return false;
      }
    } catch (e) {
      NyLogger.error('[VideoService] Error starting background download: $e');

      // Cleanup in case of error
      String downloadKey = '${courseId}_${videoId}';
      _downloadingStatus[downloadKey] = false;

      return false;
    }
  }

  // Helper method to save download info to NyStorage
  Future<void> _saveDownloadInfo({
    required String videoUrl,
    required String courseId,
    required String videoId,
    required String watermarkText,
    String email = "", // Add email parameter
    required Course course,
    required List<dynamic> curriculum,
  }) async {
    try {
      // Create download info map
      Map<String, dynamic> downloadInfo = {
        'videoUrl': videoUrl,
        'courseId': courseId,
        'videoId': videoId,
        'watermarkText': watermarkText,
        'email': email, // Store email
        'course': course.toJson(), // Convert Course to JSON
        'curriculum': curriculum,
      };

      // Save progress
      String downloadKey = '${courseId}_${videoId}';
      await NyStorage.save('progress_$downloadKey', 0.0);

      // Read current list - ensure we're working with a List
      dynamic existingData = await NyStorage.read('pending_downloads');
      List<dynamic> pendingDownloads = [];

      if (existingData is List) {
        pendingDownloads = existingData;
      } else if (existingData is String) {
        try {
          // Try to parse if it's a JSON string
          var decoded = jsonDecode(existingData);
          if (decoded is List) {
            pendingDownloads = decoded;
          }
        } catch (e) {
          // If parsing fails, start with empty list
          pendingDownloads = [];
        }
      }

      // Add new download info
      pendingDownloads.add(downloadInfo);

      // Save back to storage
      await NyStorage.save('pending_downloads', pendingDownloads);

      NyLogger.info('[VideoService] Download info saved to storage');
    } catch (e) {
      NyLogger.error('[VideoService] Error saving download info: $e');
    }
  }

  // Method to delete a downloaded video
  Future<bool> deleteVideo({
    required String courseId,
    required String videoId,
  }) async {
    try {
      // Get the video file path
      String filePath = await getVideoFilePath(courseId, videoId);
      File videoFile = File(filePath);

      // Check if file exists before attempting deletion
      if (await videoFile.exists()) {
        await videoFile.delete();

        // Update status
        String downloadKey = '${courseId}_${videoId}';
        _downloadingStatus[downloadKey] = false;
        _downloadProgress[downloadKey] = 0.0;

        // Notify about deletion
        _notifyProgressUpdate(courseId, videoId, 0.0);

        NyLogger.info(
            '[VideoService] Video deleted: $videoId in course $courseId');
        return true;
      } else {
        NyLogger.info('[VideoService] Video file not found for deletion');
        return false;
      }
    } catch (e) {
      NyLogger.error('[VideoService] Error deleting video: $e');
      return false;
    }
  }

  Future<bool> cancelDownload({
    required String courseId,
    required String videoId,
  }) async {
    try {
      String downloadKey = '${courseId}_${videoId}';

      // If not downloading, nothing to cancel
      if (_downloadingStatus[downloadKey] != true) {
        return false;
      }

      // Update status
      _downloadingStatus[downloadKey] = false;
      _downloadProgress[downloadKey] = 0.0;

      // Remove from pending downloads
      await _removeFromPendingDownloads(courseId, videoId);

      // Notify about cancel
      _notifyProgressUpdate(courseId, videoId, 0.0);

      NyLogger.info(
          '[VideoService] Download canceled for video $videoId in course $courseId');
      return true;
    } catch (e) {
      NyLogger.error('[VideoService] Error canceling download: $e');
      return false;
    }
  }

  // Start download in isolated process - skipping for now due to initialization errors
  Future<void> _startIsolatedDownload({
    required String videoUrl,
    required String courseId,
    required String videoId,
    required String watermarkText,
    String email = "", // Add email parameter
    required dynamic course,
    required List<dynamic> curriculum,
  }) async {
    // Just call the download directly instead of using isolate
    try {
      String downloadKey = '${courseId}_${videoId}';

      bool success = await downloadVideo(
        videoUrl: videoUrl,
        courseId: courseId,
        videoId: videoId,
        watermarkText: watermarkText,
        email: email, // Pass email
        onProgress: (progress) {
          _notifyProgressUpdate(courseId, videoId, progress);
          NyStorage.save('progress_$downloadKey', progress);
        },
      );

      // Handle completion
      _handleDownloadComplete(
        courseId: courseId,
        videoId: videoId,
        success: success,
        course: course,
        curriculum: curriculum,
      );
    } catch (e) {
      NyLogger.error('[VideoService] Download process error: $e');

      // Handle failure
      _handleDownloadComplete(
        courseId: courseId,
        videoId: videoId,
        success: false,
        course: course,
        curriculum: curriculum,
      );
    }
  }

  // Handle download completion
  Future<void> _handleDownloadComplete({
    required String courseId,
    required String videoId,
    required bool success,
    required dynamic course,
    required List<dynamic> curriculum,
  }) async {
    String downloadKey = '${courseId}_${videoId}';

    // Update status
    _downloadingStatus[downloadKey] = false;
    if (success) {
      _downloadProgress[downloadKey] = 1.0;
      await NyStorage.save('progress_$downloadKey', 1.0);
    }

    // Remove from pending downloads
    await _removeFromPendingDownloads(courseId, videoId);

    // Log completion status
    if (success) {
      NyLogger.info(
          '[VideoService] Download completed successfully for video $videoId in course $courseId');
    } else {
      NyLogger.error(
          '[VideoService] Download failed for video $videoId in course $courseId');
    }

    // Notify listeners about completion
    _notifyProgressUpdate(courseId, videoId, success ? 1.0 : 0.0);
  }

  // Notify progress update
  void _notifyProgressUpdate(String courseId, String videoId, double progress) {
    // Add to stream
    _progressStreamController.add({
      'courseId': courseId,
      'videoId': videoId,
      'progress': progress,
    });
  }

  // Remove from pending downloads
  Future<void> _removeFromPendingDownloads(
      String courseId, String videoId) async {
    try {
      // Get pending downloads - handle possible String/List type issues
      dynamic pendingDownloadsRaw = await NyStorage.read('pending_downloads');
      List<dynamic> pendingDownloads = [];

      if (pendingDownloadsRaw is List) {
        pendingDownloads = pendingDownloadsRaw;
      } else if (pendingDownloadsRaw is String) {
        try {
          // Try to parse if it's a JSON string
          var decoded = jsonDecode(pendingDownloadsRaw);
          if (decoded is List) {
            pendingDownloads = decoded;
          }
        } catch (e) {
          // If parsing fails, start with empty list
          pendingDownloads = [];
        }
      }

      // Filter out the download to remove
      List<dynamic> updatedDownloads = [];

      for (dynamic item in pendingDownloads) {
        try {
          Map<String, dynamic> downloadData;
          if (item is String) {
            downloadData = jsonDecode(item);
          } else if (item is Map) {
            downloadData = Map<String, dynamic>.from(item);
          } else {
            continue; // Skip invalid items
          }

          if (downloadData['courseId'] != courseId ||
              downloadData['videoId'] != videoId) {
            updatedDownloads.add(item);
          }
        } catch (e) {
          // Keep any items that can't be parsed
          updatedDownloads.add(item);
        }
      }

      // Save updated list
      await NyStorage.save('pending_downloads', updatedDownloads);
    } catch (e) {
      NyLogger.error(
          '[VideoService] Error removing from pending downloads: $e');
    }
  }

  // Method to check if video is downloaded
  Future<bool> isVideoDownloaded({
    required String videoUrl,
    required String courseId,
    required String videoId,
  }) async {
    try {
      // Get the video file path
      String filePath = await getVideoFilePath(courseId, videoId);
      File videoFile = File(filePath);
      return videoFile.existsSync();
    } catch (e) {
      NyLogger.error('[VideoService] Error checking downloaded video: $e');
      return false;
    }
  }

  // Method to check if video can be played
  Future<bool> canPlayVideo({
    required String videoUrl,
    required String courseId,
    required String videoId,
  }) async {
    // Only downloaded videos can be played as per requirements
    return await isVideoDownloaded(
      videoUrl: videoUrl,
      courseId: courseId,
      videoId: videoId,
    );
  }

  // Method to download video with watermark and progress tracking
  Future<bool> downloadVideo({
    required String videoUrl,
    required String courseId,
    required String videoId,
    required String watermarkText,
    String email = "",
    Function(double)? onProgress,
  }) async {
    try {
      // Request storage permission
      var status = await Permission.storage.request();
      if (!status.isGranted) {
        NyLogger.error('[VideoService] Storage permission denied');
        return false;
      }

      // Create app directory if it doesn't exist
      Directory appDir = await getApplicationDocumentsDirectory();
      String courseDir = '${appDir.path}/courses/$courseId/videos';
      await Directory(courseDir).create(recursive: true);

      // Create assets directory and extract logo if needed
      String assetsDir = '${appDir.path}/public';
      await Directory('$assetsDir/images').create(recursive: true);
      String logoPath = '$assetsDir/images/trans_logo.png';

      // Ensure we have the logo file extracted
      await _extractLogoFile(logoPath);

      // Temporary file for downloaded video
      String tempFilePath = '$courseDir/temp_$videoId.mp4';
      File tempFile = File(tempFilePath);

      // Get output file path for final video
      String outputPath = await getVideoFilePath(courseId, videoId);

      // First attempt to validate the URL is actually a video file
      NyLogger.info('[VideoService] Validating video URL: $videoUrl');

      // Check if URL is a direct video file (basic check)
      if (!_isLikelyVideoUrl(videoUrl)) {
        NyLogger.error(
            '[VideoService] URL does not appear to be a direct video file: $videoUrl');
        // Continue anyway, we'll validate the content after download
      }

      // Prepare headers with proper User-Agent to avoid being blocked
      Map<String, String> headers = {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        'Accept': '*/*',
      };

      try {
        // Try to get headers of the URL to check content type
        var headResponse =
            await http.head(Uri.parse(videoUrl), headers: headers);
        String? contentType = headResponse.headers['content-type'];

        if (contentType == null || !contentType.contains('video')) {
          NyLogger.error(
              '[VideoService] URL content type is not video: $contentType');

          // If content type is HTML, this might be a webpage, not a direct video link
          if (contentType?.contains('text/html') == true) {
            NyLogger.error(
                '[VideoService] URL appears to be a webpage, not a direct video file');
            // Continue anyway - some servers might not properly set content type
          }
        }
      } catch (e) {
        NyLogger.error('[VideoService] Error checking video URL headers: $e');
        // Continue anyway, might still be a valid file
      }

      // Download the video with progress tracking using Dio
      NyLogger.info('[VideoService] Downloading video: $videoUrl');

      try {
        // Set timeout to avoid hanging
        _dio.options.connectTimeout = const Duration(seconds: 30);
        _dio.options.receiveTimeout = const Duration(seconds: 60);
        _dio.options.headers = headers;

        await _dio.download(
          videoUrl,
          tempFilePath,
          onReceiveProgress: (received, total) {
            if (total != -1) {
              double progress = received / total;
              if (onProgress != null) {
                onProgress(progress * 0.7); // First 70% is for downloading
              }
              NyLogger.info(
                  '[VideoService] Download progress: ${(progress * 100).toStringAsFixed(1)}%');
            }
          },
        );
      } catch (e) {
        NyLogger.error('[VideoService] Failed to download video with Dio: $e');

        // If download failed with Dio, try with regular http
        try {
          NyLogger.info(
              '[VideoService] Trying alternative download method with http');
          var response = await http.get(Uri.parse(videoUrl), headers: headers);
          if (response.statusCode == 200) {
            await tempFile.writeAsBytes(response.bodyBytes);
            NyLogger.info('[VideoService] Alternative download succeeded');
          } else {
            NyLogger.error(
                '[VideoService] Alternative download failed: ${response.statusCode}');
            return false;
          }
        } catch (e) {
          NyLogger.error('[VideoService] Alternative download failed: $e');
          return false;
        }
      }

      // Check if file was downloaded and is a valid video file
      if (!await tempFile.exists()) {
        NyLogger.error(
            '[VideoService] Temp file does not exist after download attempt');
        return false;
      }

      // Check file size
      int fileSize = await tempFile.length();
      if (fileSize < 1000) {
        // Less than 1KB is suspicious
        NyLogger.error(
            '[VideoService] Downloaded file is too small: $fileSize bytes');

        // Read the first few bytes to check if it's HTML or error message
        String fileContent = await tempFile
            .openRead(0, 100)
            .transform(const Utf8Decoder())
            .join();
        if (fileContent.contains('<!DOCTYPE') ||
            fileContent.contains('<html')) {
          NyLogger.error('[VideoService] Downloaded file is HTML, not a video');
          return false;
        }
      }

      // Validate file as a video
      try {
        String? mimeType = lookupMimeType(tempFilePath);
        if (mimeType == null || !mimeType.startsWith('video/')) {
          NyLogger.error(
              '[VideoService] Downloaded file MIME type is not video: $mimeType');

          // Try to use FFprobe (part of FFmpeg) to check file
          final session = await FFmpegKit.execute('-y -i $tempFilePath');
          final returnCode = await session.getReturnCode();

          // FFmpeg will actually return an error code for this command, but the logs will contain the file info
          final logs = await session.getLogs();
          bool isVideo = false;
          for (Log log in logs) {
            String message = log.getMessage();
            if (message.contains('Video:') || message.contains('Duration:')) {
              isVideo = true;
              break;
            }
          }

          if (!isVideo) {
            NyLogger.error(
                '[VideoService] FFmpeg could not identify file as a video');
            return false;
          }
        }
      } catch (e) {
        NyLogger.error('[VideoService] Error validating downloaded file: $e');
        // Continue anyway as FFmpeg might still be able to process it
      }

      // Try to copy the file directly first without watermark to see if it's valid
      NyLogger.info('[VideoService] Testing file validity by copying');

      // Delete any existing test file to avoid overwrite prompt
      File testFile = File('${tempFilePath}_test.mp4');
      if (await testFile.exists()) {
        await testFile.delete();
      }

      final testSession = await FFmpegKit.execute(
          '-y -i $tempFilePath -c copy ${tempFilePath}_test.mp4');

      final testReturnCode = await testSession.getReturnCode();
      if (!ReturnCode.isSuccess(testReturnCode)) {
        NyLogger.error(
            '[VideoService] File verification failed - not a valid video');

        // Log detailed error information
        final logs = await testSession.getLogs();
        for (Log log in logs) {
          NyLogger.error('[VideoService] FFmpeg log: ${log.getMessage()}');
        }

        // Delete the corrupted temp file
        if (await tempFile.exists()) {
          await tempFile.delete();
        }

        return false;
      }

      // If we've reached here, the file is valid - continue with watermarking
      NyLogger.info(
          '[VideoService] Adding logo and username watermark to video');

      // First check if the logo file is valid and readable by FFmpeg
      if (File(logoPath).existsSync()) {
        final logoValidation =
            await FFmpegKit.execute('-y -i $logoPath -f null -');
        final logoReturnCode = await logoValidation.getReturnCode();

        if (!ReturnCode.isSuccess(logoReturnCode)) {
          NyLogger.error(
              '[VideoService] Logo file validation failed - may not be usable by FFmpeg');
          // We'll continue but might fall back to text-only watermark
        } else {
          NyLogger.info('[VideoService] Logo file validated successfully');
        }
      }

      // Try the two-step approach first
      bool watermarkSuccess = false;

      // Clean up any existing intermediate files
      File intermediateFile = File('${tempFilePath}_with_logo.mp4');
      if (await intermediateFile.exists()) {
        await intermediateFile.delete();
      }

      if (File(logoPath).existsSync()) {
        NyLogger.info('[VideoService] Trying two-step watermarking approach');

        // Step 1: Apply just the logo overlay with simplified scaling
        final logoOnlyCommand =
            '-y -i $tempFilePath -i $logoPath -filter_complex '
            '"[1:v]scale=100:-1[logo];[0:v][logo]overlay=10:H-h-10" '
            '-codec:a copy ${tempFilePath}_with_logo.mp4';

        final logoSession = await FFmpegKit.execute(logoOnlyCommand);
        final logoReturnCode = await logoSession.getReturnCode();

        if (ReturnCode.isSuccess(logoReturnCode)) {
          NyLogger.info(
              '[VideoService] Logo overlay succeeded, adding text watermark');

          // Step 2: Add text watermark to the logo-watermarked video
          final textCommand = '-y -i ${tempFilePath}_with_logo.mp4 -vf '
              '"drawtext=text=\'$watermarkText\':fontcolor=white:fontsize=24:x=W-tw-10:y=H-th-10:box=1:boxcolor=black@0.5:boxborderw=5" '
              '-codec:a copy $outputPath';

          final textSession = await FFmpegKit.execute(textCommand);
          final textReturnCode = await textSession.getReturnCode();

          if (ReturnCode.isSuccess(textReturnCode)) {
            NyLogger.info('[VideoService] Two-step watermark succeeded');
            watermarkSuccess = true;
          } else {
            NyLogger.error('[VideoService] Text watermark step failed');
            // Log errors
            final logs = await textSession.getLogs();
            for (Log log in logs) {
              NyLogger.error('[VideoService] FFmpeg log: ${log.getMessage()}');
            }
          }
        } else {
          NyLogger.error('[VideoService] Logo overlay step failed');
          // Log errors
          final logs = await logoSession.getLogs();
          for (Log log in logs) {
            NyLogger.error('[VideoService] FFmpeg log: ${log.getMessage()}');
          }
        }

        // Clean up intermediate file regardless of success
        if (await intermediateFile.exists()) {
          await intermediateFile.delete();
        }
      }

      // If two-step approach failed, try the original approach
      if (!watermarkSuccess) {
        // Original combined approach with fixes
        NyLogger.info('[VideoService] Trying original watermarking approach');

        // Create watermarking command with logo and text (with -y flag)
        String ffmpegCommand = _createWatermarkCommand(
            tempFilePath, outputPath, logoPath, watermarkText, email);

        // Add -y flag if not present
        if (!ffmpegCommand.startsWith('-y')) {
          ffmpegCommand = '-y ' + ffmpegCommand;
        }

        NyLogger.info(
            '[VideoService] Executing FFmpeg command: $ffmpegCommand');

        final session =
            await FFmpegKit.executeAsync(ffmpegCommand, (Session) async {
          final returnCode = await Session.getReturnCode();

          // Add detailed logging for FFmpeg output
          final logs = await Session.getLogs();
          NyLogger.info('[VideoService] FFmpeg logs count: ${logs.length}');
          for (Log log in logs) {
            NyLogger.info('[VideoService] FFmpeg log: ${log.getMessage()}');
          }

          // Delete temp file
          if (await tempFile.exists()) {
            await tempFile.delete();
          }

          if (ReturnCode.isSuccess(returnCode)) {
            NyLogger.info(
                '[VideoService] FFmpeg processing completed successfully');
            if (onProgress != null) {
              onProgress(1.0); // 100% complete
            }
          } else {
            NyLogger.error(
                '[VideoService] FFmpeg process failed with return code: $returnCode');
          }
        }, (Log log) {
          // Add real-time log callback
          NyLogger.info(
              '[VideoService] FFmpeg real-time log: ${log.getMessage()}');
        }, (Statistics stats) {
          if (onProgress != null) {
            // Progress from 70% to 100% during encoding
            double ffmpegProgress = 0.7 +
                (stats.getTime() / 5000) *
                    0.3; // Assuming video is around 5 seconds
            ffmpegProgress = ffmpegProgress > 1.0 ? 1.0 : ffmpegProgress;
            onProgress(ffmpegProgress);
          }
        });

        // Wait for FFmpeg to complete
        final returnCode = await session.getReturnCode();

        if (ReturnCode.isSuccess(returnCode)) {
          NyLogger.info('[VideoService] Video processed successfully');
          watermarkSuccess = true;
        }
      }

      // If both approaches failed, try text-only or direct copy
      if (!watermarkSuccess) {
        // Try alternative method with simpler command if previous attempts failed
        NyLogger.error(
            '[VideoService] Previous watermark attempts failed, trying text-only watermark');

        if (await tempFile.exists()) {
          // Try with text-only watermark (with -y flag)
          final simpleCommand =
              '-y -i $tempFilePath -vf "drawtext=text=\'Bhavani $watermarkText\':fontcolor=white:fontsize=24:x=10:y=h-th-10:box=1:boxcolor=black@0.5:boxborderw=5" '
              '-codec:a copy $outputPath';

          final backupSession = await FFmpegKit.execute(simpleCommand);
          final backupReturnCode = await backupSession.getReturnCode();

          if (ReturnCode.isSuccess(backupReturnCode)) {
            NyLogger.info('[VideoService] Text-only watermark succeeded');
            return true;
          } else {
            NyLogger.error(
                '[VideoService] Text-only watermark failed, trying direct copy');

            // Last resort: try a direct copy without watermark
            final lastSession = await FFmpegKit.execute(
                '-y -i $tempFilePath -c copy $outputPath');

            final lastReturnCode = await lastSession.getReturnCode();

            if (ReturnCode.isSuccess(lastReturnCode)) {
              NyLogger.info('[VideoService] Direct copy succeeded');
              return true;
            } else {
              NyLogger.error('[VideoService] All FFmpeg attempts failed');

              // Log detailed error information
              final logs = await lastSession.getLogs();
              for (Log log in logs) {
                NyLogger.error(
                    '[VideoService] FFmpeg log: ${log.getMessage()}');
              }

              return false;
            }
          }
        } else {
          NyLogger.error('[VideoService] Temp file no longer exists');
          return false;
        }
      }

      return watermarkSuccess;
    } catch (e) {
      NyLogger.error('[VideoService] Error downloading video: $e');
      return false;
    } finally {
      // Cleanup any test files that might have been created
      try {
        Directory appDir = await getApplicationDocumentsDirectory();
        String courseDir = '${appDir.path}/courses/$courseId/videos';
        String tempFilePath = '$courseDir/temp_$videoId.mp4';
        File testFile = File('${tempFilePath}_test.mp4');
        if (await testFile.exists()) {
          await testFile.delete();
        }
      } catch (e) {
        // Ignore cleanup errors
      }
    }
  }

  // Method to play video using Nylo routing
  Future<void> playVideo({
    required String videoUrl,
    required String courseId,
    required String videoId,
    required String watermarkText,
    required BuildContext context,
  }) async {
    try {
      // Get file path
      String videoPath = await getVideoFilePath(courseId, videoId);
      File videoFile = File(videoPath);

      // Check if file exists
      if (await videoFile.exists()) {
        // Play video using Nylo's routeTo with VideoPlayerPage
        routeTo(VideoPlayerPage.path, data: {
          'videoPath': videoPath,
          'watermarkText': watermarkText,
        });
      } else {
        // Show error - videos must be downloaded first
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(trans("Please download the video first")),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      NyLogger.error('[VideoService] Error playing video: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(trans("Failed to play video")),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // Method to get video file path
  Future<String> getVideoFilePath(String courseId, String videoId) async {
    Directory appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/courses/$courseId/videos/video_$videoId.mp4';
  }

  // Helper method to extract logo file from assets
  Future<void> _extractLogoFile(String logoPath) async {
    File logoFile = File(logoPath);

    // Check if logo file already exists
    if (!await logoFile.exists()) {
      try {
        // Create the directory structure if it doesn't exist
        Directory(path.dirname(logoPath)).createSync(recursive: true);

        // Try multiple possible paths for the logo
        List<String> possiblePaths = [
          'public/images/trans_logo.png',
          'assets/images/trans_logo.png',
          'assets/public/images/trans_logo.png',
        ];

        ByteData? data;
        for (String path in possiblePaths) {
          try {
            data = await rootBundle.load(path);
            NyLogger.info('[VideoService] Found logo at: $path');
            break; // Break once we find a valid path
          } catch (e) {
            NyLogger.error('[VideoService] Logo not found at: $path');
            // Continue to the next path
          }
        }

        if (data != null) {
          List<int> bytes = data.buffer.asUint8List();
          await logoFile.writeAsBytes(bytes);
          NyLogger.info('[VideoService] Logo extracted to: $logoPath');
        } else {
          throw Exception('Logo not found in any of the expected paths');
        }
      } catch (e) {
        // If loading from assets fails, log and continue without logo
        NyLogger.error('[VideoService] Error extracting logo: $e');
        NyLogger.info('[VideoService] Will use text-only watermark');
      }
    }
  }

  // Helper method to create watermark command based on file existence
  String _createWatermarkCommand(
      String inputPath, String outputPath, String logoPath, String username,
      [String email = ""]) {
    File logoFile = File(logoPath);
    // Check if logo file exists without awaiting
    String watermarkText = username;
    if (email.isNotEmpty) {
      watermarkText = "$username\\n$email"; // Use \n for newline in FFmpeg text
    }
    if (logoFile.existsSync()) {
      // Simplified command to overlay logo with scaling and text
      return '-y -i $inputPath -i $logoPath -filter_complex '
          '"[1:v]scale=100:-1[logo];[0:v][logo]overlay=10:main_h-overlay_h-10, '
          'drawtext=text=\'$watermarkText\':fontcolor=white:fontsize=24:x=w-tw-10:y=h-th-10:box=1:boxcolor=black@0.5:boxborderw=5" '
          '-codec:a copy $outputPath';
    } else {
      // Fallback to text-only watermark with -y flag
      return '-y -i $inputPath -vf "drawtext=text=\'Bhavani $watermarkText\':fontcolor=white:fontsize=24:x=10:y=h-th-10:box=1:boxcolor=black@0.5:boxborderw=5" '
          '-codec:a copy $outputPath';
    }
  }

  // Helper method to check if URL is likely a video
  bool _isLikelyVideoUrl(String url) {
    String lowercaseUrl = url.toLowerCase();
    return lowercaseUrl.endsWith('.mp4') ||
        lowercaseUrl.endsWith('.mov') ||
        lowercaseUrl.endsWith('.avi') ||
        lowercaseUrl.endsWith('.webm') ||
        lowercaseUrl.endsWith('.mkv') ||
        lowercaseUrl.contains('video');
  }

  // Dispose resources when service is no longer needed
  void dispose() {
    _progressStreamController.close();
  }
}
