import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'package:flutter_app/app/models/course.dart';
import 'package:flutter_app/app/services/video_service.dart';
import 'package:flutter_app/resources/pages/video_player_page.dart';

class CourseCurriculumPage extends NyStatefulWidget {
  static RouteView path = ("/course-curriculum", (_) => CourseCurriculumPage());

  CourseCurriculumPage({super.key})
      : super(child: () => _CourseCurriculumPageState());
}

class _CourseCurriculumPageState extends NyPage<CourseCurriculumPage> {
  // Data variables
  List<dynamic> curriculumItems = [];
  Course? course;
  String courseName = "";
  String totalVideos = "";
  String totalDuration = "";

  // Pagination variables
  int _currentPage = 1;
  int _itemsPerPage = 7;
  int _totalPages = 1;

  // Download status tracking
  Map<int, bool> _downloadingStatus = {};
  Map<int, bool> _downloadedStatus = {};
  Map<int, double> _downloadProgress =
      {}; // Store download progress for each item

  // Service
  final VideoService _videoService = VideoService();

  // Stream subscription for progress updates
  StreamSubscription? _progressSubscription;

  // User information
  String _username = "User";
  String _email = "";

  @override
  void initState() {
    super.initState();

    // Listen for download progress updates
    _progressSubscription = _videoService.progressStream.listen((update) {
      if (course == null) return;

      if (update.containsKey('courseId') &&
          update.containsKey('videoId') &&
          update.containsKey('progress')) {
        String courseId = update['courseId'];
        String videoId = update['videoId'];
        double progress = update['progress'];

        // Only update if this is for our current course
        if (courseId == course!.id.toString()) {
          // Find the corresponding index
          try {
            int index = int.parse(videoId);
            if (index >= 0 && index < curriculumItems.length) {
              setState(() {
                _downloadProgress[index] = progress;
                _downloadingStatus[index] = progress < 1.0;
                _downloadedStatus[index] = progress >= 1.0;
              });
            }
          } catch (e) {
            NyLogger.error('[CourseCurriculumPage] Error parsing videoId: $e');
          }
        }
      }
    });
  }

  @override
  void dispose() {
    // Cancel stream subscription to avoid memory leaks
    _progressSubscription?.cancel();
    super.dispose();
  }

  @override
  get init => () async {
        setLoading(true);

        try {
          // Get data passed from previous page
          Map<String, dynamic> data = widget.data();

          // Extract course data
          if (data.containsKey('course') && data['course'] != null) {
            course = data['course'];
            courseName = course?.title ?? "Course Curriculum";

            // Set video count display
            totalVideos = "${curriculumItems.length} Videos";

            // Set duration display
            totalDuration = "- hours .. minutes";
          } else {
            courseName = "Course Curriculum";
            totalVideos = "Videos";
            totalDuration = "Total length";
          }

          // Extract curriculum items
          if (data.containsKey('curriculum') && data['curriculum'] != null) {
            curriculumItems = List<dynamic>.from(data['curriculum']);

            // Update total videos count if not already set
            if (!totalVideos.contains("Videos")) {
              totalVideos = "${curriculumItems.length} Videos";
            }
          } else {
            // Empty list if no curriculum provided
            curriculumItems = [];
          }

          // Calculate total pages
          _totalPages = (curriculumItems.length / _itemsPerPage).ceil();
          if (_totalPages < 1) _totalPages = 1; // Ensure at least one page

          // Get username for watermarking
          try {
            var user = await Auth.data();
            if (user != null && user.containsKey('full_name')) {
              _username = user['full_name'];
            }

            if (user != null && user.containsKey('email')) {
              _email = user['email'];
            }
          } catch (e) {
            NyLogger.error('[CourseCurriculumPage] Error getting username: $e');
          }

          // Initialize progress tracking
          for (int i = 0; i < curriculumItems.length; i++) {
            _downloadProgress[i] = 0.0;
          }

          // Check download status for each video
          await _checkDownloadedVideos();
        } catch (e) {
          NyLogger.error(
              '[CourseCurriculumPage] Error initializing curriculum page: $e');
        } finally {
          setLoading(false);
        }
      };

  Future<void> _checkDownloadedVideos() async {
    if (course == null) return;

    for (var i = 0; i < curriculumItems.length; i++) {
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

        // Get current progress
        double progress = 0.0;
        if (isDownloading) {
          progress = _videoService.getProgress(courseIdStr, videoIdStr);
        } else if (isDownloaded) {
          progress = 1.0; // If downloaded, progress is 100%
        }

        setState(() {
          _downloadedStatus[i] = isDownloaded;
          _downloadingStatus[i] = isDownloading;
          _downloadProgress[i] = progress;
        });
      }
    }
  }

  // New method to handle canceling a download
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
        _downloadProgress[index] = 0.0;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(trans("Download canceled")),
          backgroundColor: Colors.blue,
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

  // Modified method to allow redownload
  Future<void> _downloadVideo(int index, {bool isRedownload = false}) async {
    if (course == null) return;

    // If already downloading, don't start a new download
    if (_downloadingStatus[index] == true && !isRedownload) return;

    var item = curriculumItems[index];
    if (!item.containsKey('video_url') || item['video_url'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(trans("Video URL not available")),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    // If redownloading, delete the existing file first
    if (isRedownload) {
      final String courseIdStr = course!.id.toString();
      final String videoIdStr = index.toString();

      bool deleted = await _videoService.deleteVideo(
        courseId: courseIdStr,
        videoId: videoIdStr,
      );

      if (!deleted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(trans("Could not delete existing video")),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }

      // Update status after deletion
      setState(() {
        _downloadedStatus[index] = false;
      });
    }

    setState(() {
      _downloadingStatus[index] = true;
      _downloadProgress[index] = 0.0;
    });

    try {
      // Start background download process, now with email
      bool success = await _videoService.startBackgroundDownload(
        videoUrl: item['video_url'],
        courseId: course!.id.toString(),
        videoId: index.toString(),
        watermarkText: _username,
        email: _email, // Pass email for watermark
        course: course!, // Pass course for later navigation
        curriculum: curriculumItems, // Pass curriculum for later navigation
      );

      if (!success) {
        setState(() {
          _downloadingStatus[index] = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(trans("Failed to start download")),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(trans("Download started in background")),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      NyLogger.error('[CourseCurriculumPage] Error starting download: $e');
      setState(() {
        _downloadingStatus[index] = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(trans("Download failed: $e")),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _playVideo(int index) async {
    if (course == null) return;

    var item = curriculumItems[index];
    bool isDownloaded = _downloadedStatus[index] ?? false;

    if (isDownloaded) {
      await _videoService.playVideo(
        videoUrl: item['video_url'],
        courseId: course!.id.toString(),
        videoId: index.toString(),
        watermarkText:
            _username, // The player should also display email in watermark
        context: context,
      );
    } else {
      // Prompt to download
      await showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(trans("Video not downloaded")),
            content: Text(trans("Do you want to download this video now?")),
            actions: [
              TextButton(
                child: Text(trans("Cancel")),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
              TextButton(
                child: Text(trans("Download Now")),
                onPressed: () {
                  Navigator.of(context).pop();
                  _downloadVideo(index);
                },
              ),
            ],
          );
        },
      );
    }
  }

  // Modified to show options when video is downloading or downloaded
  void _handleVideoTap(int index) {
    bool isDownloaded = _downloadedStatus[index] ?? false;
    bool isDownloading = _downloadingStatus[index] ?? false;

    if (isDownloading) {
      _showDownloadingOptions(index);
    } else if (isDownloaded) {
      _showDownloadedOptions(index);
    } else {
      _downloadVideo(index);
    }
  }

  // New method to show options for downloaded videos
  void _showDownloadedOptions(int index) {
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
                ListTile(
                  leading: Icon(Icons.play_circle_outline, color: Colors.amber),
                  title: Text(trans("Play video")),
                  onTap: () {
                    Navigator.pop(context);
                    _playVideo(index);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.refresh, color: Colors.blue),
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

  // New method to show options for downloading videos
  void _showDownloadingOptions(int index) {
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
                  child: LinearProgressIndicator(
                    value: _downloadProgress[index],
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.amber),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(
                    "${(_downloadProgress[index]! * 100).toInt()}% ${trans("Downloaded")}",
                    style: TextStyle(
                      color: Colors.amber,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
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

  // New method to confirm redownload
  void _showRedownloadConfirmation(int index) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(trans("Redownload video")),
          content: Text(trans(
              "Do you want to delete the current file and download again?")),
          actions: [
            TextButton(
              child: Text(trans("Cancel")),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text(trans("Redownload")),
              style: TextButton.styleFrom(foregroundColor: Colors.blue),
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

  // New method to confirm delete
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

  // New method to delete a video
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
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(trans("Video deleted")),
          backgroundColor: Colors.blue,
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

  void _nextPage() {
    if (_currentPage < _totalPages) {
      setState(() {
        _currentPage++;
      });
    }
  }

  void _previousPage() {
    if (_currentPage > 1) {
      setState(() {
        _currentPage--;
      });
    }
  }

  @override
  Widget view(BuildContext context) {
    // Calculate items for current page
    List<dynamic> currentPageItems = [];

    if (curriculumItems.isNotEmpty) {
      int startIndex = (_currentPage - 1) * _itemsPerPage;
      int endIndex = startIndex + _itemsPerPage;
      if (endIndex > curriculumItems.length) {
        endIndex = curriculumItems.length;
      }

      currentPageItems = curriculumItems.sublist(startIndex, endIndex);
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false, // Don't show default back button
        leading: Padding(
          padding: const EdgeInsets.only(left: 10.0),
          child: IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => pop(),
            padding: EdgeInsets.zero,
          ),
        ),
        titleSpacing: 0, // Remove default title spacing
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
            SizedBox(height: 2), // Tiny gap between the lines
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
      ),
      body: afterLoad(
        child: () => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Divider
            Divider(height: 1, thickness: 1, color: Colors.grey[200]),

            // Curriculum list or empty state
            Expanded(
              child: curriculumItems.isEmpty
                  ? _buildEmptyState()
                  : ListView.separated(
                      padding: EdgeInsets.zero, // Remove default padding
                      itemCount: currentPageItems.length,
                      separatorBuilder: (context, index) => Divider(
                        height: 1,
                        thickness: 1,
                        color: Colors.grey[200],
                      ),
                      itemBuilder: (context, index) {
                        final globalIndex =
                            (_currentPage - 1) * _itemsPerPage + index;
                        final item = currentPageItems[index];
                        final bool isDownloaded =
                            _downloadedStatus[globalIndex] ?? false;
                        final bool isDownloading =
                            _downloadingStatus[globalIndex] ?? false;
                        final double progress =
                            _downloadProgress[globalIndex] ?? 0.0;

                        return _buildLessonItem(
                          (globalIndex + 1).toString(),
                          item['title'] ?? 'Video',
                          item['duration'] ?? '-:--',
                          isDownloaded: isDownloaded,
                          isDownloading: isDownloading,
                          progress: progress,
                          onTap: () => _handleVideoTap(globalIndex),
                        );
                      },
                    ),
            ),

            // Pagination Controls - show only if there's more than one page
            if (_totalPages > 1 && curriculumItems.isNotEmpty)
              Container(
                padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.shade200,
                      blurRadius: 4,
                      offset: Offset(0, -2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Previous page button
                    IconButton(
                      icon: Icon(Icons.arrow_back_ios, size: 16),
                      onPressed: _currentPage > 1 ? _previousPage : null,
                      color: _currentPage > 1
                          ? Colors.black
                          : Colors.grey.shade400,
                    ),

                    // Page indicator
                    Text(
                      "Page $_currentPage of $_totalPages",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),

                    // Next page button
                    IconButton(
                      icon: Icon(Icons.arrow_forward_ios, size: 16),
                      onPressed: _currentPage < _totalPages ? _nextPage : null,
                      color: _currentPage < _totalPages
                          ? Colors.black
                          : Colors.grey.shade400,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
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
    required double progress,
    required VoidCallback onTap,
  }) {
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
                  color: isDownloaded ? Colors.amber : Colors.black,
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
                      color: isDownloaded ? Colors.amber : Colors.black,
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
                  // Show progress bar if downloading
                  if (isDownloading)
                    Container(
                      margin: EdgeInsets.only(top: 4),
                      height: 3,
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.grey[300],
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.amber),
                      ),
                    ),
                ],
              ),
            ),

            // Action button (play, download, or loading)
            isDownloading
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "${(progress * 100).toInt()}%",
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.amber,
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
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.amber),
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
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isDownloaded
                            ? Icons.play_circle_outline
                            : Icons.download_outlined,
                        color: isDownloaded ? Colors.amber : Colors.grey[400],
                        size: 24,
                      ),
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
