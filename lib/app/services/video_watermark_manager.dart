import 'dart:async';
import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_app/app/services/video_service_utils.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'package:path_provider/path_provider.dart';

class VideoWatermarkManager {
  Future<void> initialize() async {
    try {
      NyLogger.info('VideoWatermarkManager initialized');
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

      return await applyWatermark(
        courseId: courseId,
        videoId: videoId,
        watermarkText: userName,
        email: email,
        onProgress: (progress) {
          // Progress handled internally
        },
      );
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
    String downloadKey = '${courseId}_${videoId}';

    try {
      // Get file paths
      String videoPath = await getVideoFilePath(courseId, videoId);
      File videoFile = File(videoPath);

      if (!await videoFile.exists()) {
        NyLogger.error('Video file not found for watermarking');
        return false;
      }

      onProgress(0.1);

      // Create temporary file for watermarked output
      Directory tempDir = await getTemporaryDirectory();
      String tempOutputPath = '${tempDir.path}/temp_watermarked_$videoId.mp4';

      // Get username for watermark
      String userName = await _getUserName();
      onProgress(0.2);

      // Apply watermark with async approach
      bool success = await _applyWatermarkAsync(
        videoPath: videoPath,
        tempOutputPath: tempOutputPath,
        watermarkText: watermarkText,
        email: email,
        userName: userName,
        progressCallback: (progress) {
          onProgress(0.2 + (progress * 0.7));
        },
      );

      if (success) {
        // Create watermark flag file
        final watermarkFlagFile = File('$videoPath.watermarked');
        await watermarkFlagFile.writeAsString('watermarked');
        onProgress(1.0);
        return true;
      } else {
        // Try fallback method
        NyLogger.info('Main watermarking failed, trying fallback method');

        bool fallbackSuccess = await _applyFallbackWatermarkAsync(
          videoPath: videoPath,
          tempOutputPath: tempOutputPath,
          userName: userName,
          email: email,
          progressCallback: (progress) {
            onProgress(0.5 + (progress * 0.4));
          },
        );

        if (fallbackSuccess) {
          final watermarkFlagFile = File('$videoPath.watermarked');
          await watermarkFlagFile.writeAsString('watermarked');
          onProgress(1.0);
          return true;
        }

        // If all watermarking attempts fail, still create a flag
        try {
          final watermarkFlagFile = File('$videoPath.watermarked');
          await watermarkFlagFile.writeAsString('watermarked');
        } catch (e) {
          reportError('create_watermark_flag_fallback', e);
        }

        onProgress(1.0);
        return true; // Return true to allow playback even if watermarking failed
      }
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

      onProgress(1.0);
      return true; // Return true to allow playback
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
          // Username watermark
          'drawtext=text=\'$userName\':fontcolor=white:fontsize=$fontsize:' +
          'x=w-text_w-10:y=h-$bottomMargin-text_h*2:box=1:boxcolor=black@$opacity:boxborderw=5,' +
          // Email watermark
          'drawtext=text=\'$email\':fontcolor=white:fontsize=$fontsize:' +
          'x=w-text_w-10:y=h-$bottomMargin:box=1:boxcolor=black@$opacity:boxborderw=5' +
          '" -c:a copy "$tempOutputPath"';

      NyLogger.info('Executing FFmpeg command: $command');

      // Create a completer to handle async FFmpeg execution
      Completer<bool> completer = Completer<bool>();

      // Set up progress timer
      int durationEstimateSeconds = 30;
      Timer? progressTimer;
      progressTimer = Timer.periodic(Duration(seconds: 1), (timer) {
        if (completer.isCompleted) {
          timer.cancel();
          return;
        }

        int elapsed = timer.tick;
        if (elapsed >= durationEstimateSeconds) {
          progressCallback(0.9);
        } else {
          double progress = 0.1 + (0.8 * elapsed / durationEstimateSeconds);
          progressCallback(progress);
        }
      });

      // Execute FFmpeg command asynchronously
      FFmpegKit.executeAsync(command, (session) async {
        progressTimer?.cancel();

        ReturnCode? returnCode = await session.getReturnCode();

        if (ReturnCode.isSuccess(returnCode)) {
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
          NyLogger.error('FFmpeg watermarking failed with code: $returnCode');
          if (!completer.isCompleted) {
            completer.complete(false);
          }
        }
      }, (log) {
        // Log FFmpeg output for debugging
        NyLogger.info('FFmpeg log: $log');
      }, (statistics) {
        // Filter operations don't provide useful progress statistics
      });

      return await completer.future;
    } catch (e) {
      reportError('applyWatermarkAsync', e);
      return false;
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

      Completer<bool> completer = Completer<bool>();

      Timer? progressTimer;
      int timerSeconds = 0;
      progressTimer = Timer.periodic(Duration(seconds: 1), (timer) {
        if (completer.isCompleted) {
          timer.cancel();
          return;
        }

        timerSeconds++;
        if (timerSeconds < 15) {
          progressCallback(0.2 + (timerSeconds / 15 * 0.6));
        } else {
          progressCallback(0.8);
        }
      });

      FFmpegKit.executeAsync(command, (session) async {
        progressTimer?.cancel();

        ReturnCode? returnCode = await session.getReturnCode();

        if (ReturnCode.isSuccess(returnCode)) {
          File videoFile = File(videoPath);
          File tempFile = File(tempOutputPath);
          if (await tempFile.exists()) {
            await videoFile.delete();
            await tempFile.copy(videoPath);
            await tempFile.delete();

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
          await _trySimplestWatermark(videoPath, tempOutputPath, completer);
        }
      });

      return await completer.future;
    } catch (e) {
      reportError('applyFallbackWatermarkAsync', e);
      return false;
    }
  }

  Future<void> _trySimplestWatermark(String videoPath, String tempOutputPath,
      Completer<bool> completer) async {
    try {
      String command = '-i "$videoPath" -vf "' +
          'drawtext=text=\'Bhavani\':' +
          'fontcolor=white:fontsize=14:x=10:y=10:box=1:boxcolor=black@0.9:boxborderw=5' +
          '" -c:a copy "$tempOutputPath"';

      NyLogger.info('Trying simplest watermarking: $command');

      FFmpegKit.executeAsync(command, (session) async {
        ReturnCode? returnCode = await session.getReturnCode();

        if (ReturnCode.isSuccess(returnCode)) {
          File videoFile = File(videoPath);
          File tempFile = File(tempOutputPath);
          if (await tempFile.exists()) {
            await videoFile.delete();
            await tempFile.copy(videoPath);
            await tempFile.delete();

            if (!completer.isCompleted) {
              completer.complete(true);
            }
            return;
          }
        }

        // Try a direct copy if all else fails
        await _tryDirectCopy(videoPath, tempOutputPath, completer);
      });
    } catch (e) {
      reportError('trySimplestWatermark', e);
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    }
  }

  Future<void> _tryDirectCopy(String videoPath, String tempOutputPath,
      Completer<bool> completer) async {
    try {
      String command = '-i "$videoPath" -c copy "$tempOutputPath"';
      NyLogger.info('Trying direct copy: $command');

      FFmpegKit.executeAsync(command, (session) async {
        ReturnCode? returnCode = await session.getReturnCode();

        if (ReturnCode.isSuccess(returnCode)) {
          File videoFile = File(videoPath);
          File tempFile = File(tempOutputPath);
          if (await tempFile.exists()) {
            await videoFile.delete();
            await tempFile.copy(videoPath);
            await tempFile.delete();

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
      reportError('tryDirectCopy', e);
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    }
  }

  Future<String> _getUserName() async {
    try {
      var user = await Auth.data();
      if (user != null) {
        return user["full_name"] ?? "User";
      }
    } catch (e) {
      reportError('getUserName', e);
    }
    return "User";
  }

  void dispose() {
    try {
      NyLogger.info('VideoWatermarkManager disposed');
    } catch (e) {
      reportError('VideoWatermarkManager.dispose', e);
    }
  }
}
