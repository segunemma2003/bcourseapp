import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'package:video_player/video_player.dart';

import '../../app/models/course.dart';

class CourseVideoPlayerPage extends NyStatefulWidget {
  static RouteView path =
      ("/course-video-player", (_) => CourseVideoPlayerPage());

  CourseVideoPlayerPage({super.key})
      : super(child: () => _CourseVideoPlayerPageState());
}

class _CourseVideoPlayerPageState extends NyPage<CourseVideoPlayerPage> {
  late VideoPlayerController _controller;
  late Course _course;
  late String _videoTitle;
  late int _lessonIndex;
  String? _videoUrl;
  bool _isPlaying = false;
  bool _isFullScreen = false;
  bool _isInitialized = false;
  bool _showControls = true;
  double _currentPosition = 0;
  double _totalDuration = 0;

  @override
  get init => () async {
        final data = widget.data();
        _course = data['course'];
        _videoTitle = data['videoTitle'] ?? 'Class Introduction Video';
        _lessonIndex = data['lessonIndex'] ?? 0;

        // For demonstration, use a sample video URL
        // In production, this would come from your S3 bucket
        _videoUrl =
            "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4";

        await _initializePlayer();
      };

  Future<void> _initializePlayer() async {
    setLoading(true);

    try {
      _controller = VideoPlayerController.networkUrl(Uri(path: _videoUrl!));
      await _controller.initialize();
      _controller.addListener(_videoListener);

      // Set preferred device orientation for video
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);

      setState(() {
        _isInitialized = true;
        _totalDuration = _controller.value.duration.inSeconds.toDouble();
      });

      // Auto-play when ready
      _controller.play();
      _isPlaying = true;
    } catch (e) {
      NyLogger.error('Error initializing video player: $e');

      showToast(
          title: trans("Error"),
          description: trans("Failed to load video"),
          icon: Icons.error_outline,
          style: ToastNotificationStyleType.danger);
    } finally {
      setLoading(false);
    }
  }

  void _videoListener() {
    if (_controller.value.isInitialized && mounted) {
      setState(() {
        _isPlaying = _controller.value.isPlaying;
        _currentPosition = _controller.value.position.inSeconds.toDouble();
      });
    }
  }

  void _togglePlayPause() {
    if (_isPlaying) {
      _controller.pause();
    } else {
      _controller.play();
    }
    setState(() {
      _isPlaying = !_isPlaying;
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  void _toggleFullScreen() {
    setState(() {
      _isFullScreen = !_isFullScreen;
    });

    if (_isFullScreen) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }
  }

  void _onSliderChanged(double value) {
    _controller.seekTo(Duration(seconds: value.toInt()));
  }

  void _goBack() {
    if (_isFullScreen) {
      _toggleFullScreen();
    } else {
      Navigator.pop(context);
    }
  }

  String _formatDuration(double seconds) {
    final duration = Duration(seconds: seconds.toInt());
    final minutes = duration.inMinutes;
    final remainingSeconds = duration.inSeconds - minutes * 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _controller.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  Widget view(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Video Player
            _buildVideoPlayer(),

            // Content below video player (only shown in portrait mode)
            if (!_isFullScreen) _buildContentBelowPlayer(),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPlayer() {
    return Container(
      color: Colors.black,
      height: _isFullScreen ? MediaQuery.of(context).size.height : 240,
      child: _isInitialized
          ? Stack(
              children: [
                // Video Player
                GestureDetector(
                  onTap: _toggleControls,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    ),
                  ),
                ),

                // Video Controls Overlay (only shown when _showControls is true)
                if (_showControls) _buildVideoControls(),
              ],
            )
          : Center(
              child: CircularProgressIndicator(),
            ),
    );
  }

  Widget _buildVideoControls() {
    return Container(
      color: Colors.black.withOpacity(0.3),
      child: Stack(
        children: [
          // Back Button (top left)
          Positioned(
            top: 8,
            left: 8,
            child: IconButton(
              icon: Icon(Icons.arrow_back, color: Colors.white),
              onPressed: _goBack,
            ),
          ),

          // Fullscreen Button (top right)
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              icon: Icon(
                _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                color: Colors.white,
              ),
              onPressed: _toggleFullScreen,
            ),
          ),

          // Center Play/Pause Button
          Positioned.fill(
            child: Center(
              child: GestureDetector(
                onTap: _togglePlayPause,
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.3),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ),
            ),
          ),

          // Progress Bar and Duration (bottom)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.5),
                  ],
                ),
              ),
              child: Row(
                children: [
                  Text(
                    _formatDuration(_currentPosition),
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 2,
                        thumbShape:
                            RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape:
                            RoundSliderOverlayShape(overlayRadius: 10),
                        activeTrackColor: Colors.white,
                        inactiveTrackColor: Colors.white.withOpacity(0.3),
                        thumbColor: Colors.white,
                        overlayColor: Colors.white.withOpacity(0.2),
                      ),
                      child: Slider(
                        value: _currentPosition,
                        min: 0,
                        max: _totalDuration > 0 ? _totalDuration : 100,
                        onChanged: _onSliderChanged,
                      ),
                    ),
                  ),
                  Text(
                    _formatDuration(_totalDuration),
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentBelowPlayer() {
    return Expanded(
      child: Container(
        color: Colors.white,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Video Title and Course Info
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _videoTitle,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    _course.title,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),

            // Tutor Section
            Container(
              padding: EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tutor Image
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: _course
                          .image, // Use the image URL directly from your Course model
                      width: 120,
                      height: 80,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        width: 120,
                        height: 80,
                        color: Colors.grey.shade300,
                        child: Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.0,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  const Color(0xFFFFEB3B)),
                            ),
                          ),
                        ),
                      ),
                      errorWidget: (context, error, stackTrace) => Container(
                        width: 120,
                        height: 80,
                        color: Colors.grey.shade300,
                        child: Icon(
                          Icons
                              .image_not_supported_outlined, // Better icon for image error
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ),

                  SizedBox(width: 16),

                  // Tutor Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Pragya Rajpurohit",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          "Head Tailor",
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Actions Row
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildActionButton(Icons.replay_10, "Replay", () {
                    _controller.seekTo(
                        _controller.value.position - Duration(seconds: 10));
                  }),
                  _buildActionButton(Icons.forward_10, "Forward", () {
                    _controller.seekTo(
                        _controller.value.position + Duration(seconds: 10));
                  }),
                  _buildActionButton(Icons.speed, "Speed", _showSpeedOptions),
                  _buildActionButton(
                      Icons.fullscreen, "Expand", _toggleFullScreen),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(
      IconData icon, String label, VoidCallback onPressed) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(icon),
          onPressed: onPressed,
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }

  void _showSpeedOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSpeedOption(0.5),
              _buildSpeedOption(0.75),
              _buildSpeedOption(1.0, isSelected: true),
              _buildSpeedOption(1.25),
              _buildSpeedOption(1.5),
              _buildSpeedOption(2.0),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSpeedOption(double speed, {bool isSelected = false}) {
    return ListTile(
      title: Text(
        speed == 1.0 ? "Normal" : "${speed}x",
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.amber : Colors.black,
        ),
      ),
      leading: isSelected ? Icon(Icons.check, color: Colors.amber) : null,
      onTap: () {
        Navigator.pop(context);
        // Set playback speed
        _controller.setPlaybackSpeed(speed);
      },
    );
  }
}
