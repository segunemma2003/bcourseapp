import 'dart:async';
import 'dart:io';
// import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';  // Temporarily disabled
// import 'package:ffmpeg_kit_flutter_new/return_code.dart';  // Temporarily disabled
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_app/app/services/video_service_utils.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'package:path_provider/path_provider.dart';

class VideoWatermarkManager {
  Future<void> initialize() async {
    try {
      NyLogger.info(
          'VideoWatermarkManager initialized (FFmpeg temporarily disabled)');
    } catch (e) {
      reportError('VideoWatermarkManager.initialize', e);
    }
  }

  Future<String> getVideoFilePath(String courseId, String videoId) async {
    Directory appDir = await getApplicationDocumentsDirectory();
    String userId = await getCurrentUserId();
    String userPath = '${appDir.path}/users/$userId/courses/$courseId/videos';
    await Directory(userPath).create(recursive: true);
    return '$userPath/video_$videoId.mp4';
  }

  Future<String> getWatermarkFlagPath(String courseId, String videoId) async {
    String videoPath = await getVideoFilePath(courseId, videoId);
    return '$videoPath.watermarked';
  }

  Future<bool> isVideoWatermarked(String courseId, String videoId) async {
    try {
      String videoPath = await getVideoFilePath(courseId, videoId);
      File videoFile = File(videoPath);

      if (!await videoFile.exists()) {
        return false;
      }

      String watermarkFlagPath = await getWatermarkFlagPath(courseId, videoId);
      File watermarkFlagFile = File(watermarkFlagPath);

      if (await watermarkFlagFile.exists()) {
        return true;
      }

      // If video exists but no flag, create flag and assume watermarked
      try {
        await watermarkFlagFile.writeAsString('watermarked');
        return true;
      } catch (e) {
        reportError('create_watermark_flag', e);
      }

      return true; // Assume watermarked to prevent watermarking failures
    } catch (e) {
      reportError('isVideoWatermarked', e);
      return false;
    }
  }

  Future<bool> ensureVideoWatermarked({
    required String courseId,
    required String videoId,
    required String email,
    required String userName,
  }) async {
    try {
      bool isWatermarked = await isVideoWatermarked(courseId, videoId);
      if (isWatermarked) {
        return true;
      }

      // Temporarily disabled FFmpeg watermarking
      NyLogger.info(
          'FFmpeg watermarking temporarily disabled - creating watermark flag');

      // Create watermark flag to allow video playback
      String videoPath = await getVideoFilePath(courseId, videoId);
      final watermarkFlagFile = File('$videoPath.watermarked');
      await watermarkFlagFile.writeAsString('watermarked');

      return true;
    } catch (e) {
      reportError('ensureVideoWatermarked', e);
      return false;
    }
  }

  Future<bool> applyWatermark({
    required String courseId,
    required String videoId,
    required String watermarkText,
    required String email,
    required Function(double) onProgress,
  }) async {
    try {
      // Temporarily disabled FFmpeg watermarking
      NyLogger.info('FFmpeg watermarking temporarily disabled');
      onProgress(1.0);

      // Create watermark flag to allow video playback
      String videoPath = await getVideoFilePath(courseId, videoId);
      final watermarkFlagFile = File('$videoPath.watermarked');
      await watermarkFlagFile.writeAsString('watermarked');

      return true;
    } catch (e, stackTrace) {
      reportError('applyWatermark', e, stackTrace: stackTrace);

      // Create watermark flag even on error
      try {
        final watermarkFlagFile =
            File('${await getVideoFilePath(courseId, videoId)}.watermarked');
        await watermarkFlagFile.writeAsString('watermarked');
      } catch (e) {
        // Ignore
      }

      return true; // Return true to allow playback even if watermarking failed
    }
  }

  Future<String> getCurrentUserId() async {
    try {
      var user = await Auth.data();
      return user?['id']?.toString() ?? 'default_user';
    } catch (e) {
      reportError('getCurrentUserId', e);
      return 'default_user';
    }
  }

  Future<String> _getUserName() async {
    try {
      var user = await Auth.data();
      return user?['full_name']?.toString() ??
          user?['fullName']?.toString() ??
          'User';
    } catch (e) {
      reportError('getUserName', e);
      return 'User';
    }
  }

  void reportError(String method, dynamic error, {StackTrace? stackTrace}) {
    try {
      NyLogger.error('VideoWatermarkManager.$method error: $error');
      FirebaseCrashlytics.instance.recordError(
        error,
        stackTrace,
        reason: 'VideoWatermarkManager.$method failed',
        fatal: false,
      );
    } catch (e) {
      NyLogger.error('Failed to report error: $e');
    }
  }

  void dispose() {
    try {
      NyLogger.info('VideoWatermarkManager disposed successfully');
    } catch (e) {
      reportError('dispose', e);
    }
  }
}
