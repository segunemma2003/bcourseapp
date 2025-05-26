import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'package:video_player/video_player.dart' as vp;
import 'package:chewie/chewie.dart';
import 'dart:async';

class VideoPlayerPage extends NyStatefulWidget {
  static RouteView path = ("/video-player", (_) => VideoPlayerPage());

  VideoPlayerPage({super.key}) : super(child: () => _VideoPlayerPageState());
}

class _VideoPlayerPageState extends NyPage<VideoPlayerPage>
    with WidgetsBindingObserver {
  late vp.VideoPlayerController _videoController;
  ChewieController? _chewieController;
  bool _isInitialized = false;
  bool _hasError = false;
  String _errorMessage = "";
  bool _isFullScreen = false;

  String? videoPath;

  @override
  get init => () async {
        // Get passed data
        Map<String, dynamic> data = widget.data();
        videoPath = data['videoPath'];

        if (videoPath == null) {
          setState(() {
            _hasError = true;
            _errorMessage = "No video path provided";
          });
          return;
        }

        await _initializePlayer();
      };

  @override
  void initState() {
    super.initState();

    // Register this widget as an observer to listen for app lifecycle changes
    WidgetsBinding.instance.addObserver(this);

    // Allow all orientations
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    // Reset orientation when leaving the page
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    // Remove the observer
    WidgetsBinding.instance.removeObserver(this);

    // Remove any listeners
    if (_chewieController != null) {
      _chewieController!.removeListener(_fullscreenListener);
    }

    if (_isInitialized) {
      _videoController.dispose();
      _chewieController?.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // When app resumes, ensure our orientation settings are still applied
    if (state == AppLifecycleState.resumed) {
      if (_isFullScreen) {
        _forceLandscape();
      } else {
        _setAllOrientations();
      }
    }
  }

  Future<void> _initializePlayer() async {
    try {
      // Check if file exists
      File videoFile = File(videoPath!);
      if (!await videoFile.exists()) {
        setState(() {
          _hasError = true;
          _errorMessage = "Video file not found";
        });
        return;
      }

      // Initialize video controller
      _videoController = vp.VideoPlayerController.file(videoFile);

      // Wait for initialization
      await _videoController.initialize();

      // Configure Chewie controller with settings
      _chewieController = ChewieController(
        videoPlayerController: _videoController,
        aspectRatio: _videoController.value.aspectRatio,
        autoPlay: true,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        fullScreenByDefault: false,
        showControls: true,
        // For iOS, we'll handle device orientation manually
        deviceOrientationsAfterFullScreen: [
          DeviceOrientation.portraitUp,
        ],
        deviceOrientationsOnEnterFullScreen: [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
        // Use custom controls for iOS
        customControls: Platform.isIOS
            ? const MaterialControls(
                showPlayButton: true,
              )
            : null,
        placeholder: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.amber),
          ),
        ),
        materialProgressColors: ChewieProgressColors(
          playedColor: Colors.amber,
          handleColor: Colors.amberAccent,
          backgroundColor: Colors.grey.shade300,
          bufferedColor: Colors.grey.shade500,
        ),
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Text(
              errorMessage,
              style: TextStyle(color: Colors.white),
            ),
          );
        },
      );

      // Add listener for fullscreen changes
      _chewieController!.addListener(_fullscreenListener);

      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      NyLogger.error('Error initializing video player: $e');
      setState(() {
        _hasError = true;
        _errorMessage = "Failed to load video: $e";
      });
    }
  }

  void _fullscreenListener() {
    if (_chewieController != null &&
        _isFullScreen != _chewieController!.isFullScreen) {
      setState(() {
        _isFullScreen = _chewieController!.isFullScreen;
      });

      // Handle orientation based on fullscreen state
      if (_isFullScreen) {
        // Entered fullscreen - force landscape
        NyLogger.info('Entered fullscreen mode');
        _forceLandscape();
      } else {
        // Exited fullscreen - allow all orientations
        NyLogger.info('Exited fullscreen mode');
        _setAllOrientations();
      }
    }
  }

  void _setAllOrientations() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  // Force landscape orientation
  void _forceLandscape() {
    Future.delayed(Duration(milliseconds: 100), () {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);

      // For iOS, ensure the orientation change is applied
      if (Platform.isIOS) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky)
            .then((_) {
          Future.delayed(Duration(milliseconds: 200), () {
            SystemChrome.setPreferredOrientations([
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]);
          });
        });
      }
    });
  }

  // Toggle fullscreen
  void _toggleFullScreen() {
    if (_chewieController != null) {
      _chewieController!.toggleFullScreen();
    }
  }

  @override
  Widget view(BuildContext context) {
    return WillPopScope(
      // Handle back button press
      onWillPop: () async {
        // If in fullscreen, exit fullscreen instead of navigating back
        if (_isFullScreen && _chewieController != null) {
          _chewieController!.exitFullScreen();
          return false; // Prevent navigation
        }
        return true; // Allow navigation
      },
      child: OrientationBuilder(
        builder: (context, orientation) {
          return Scaffold(
            backgroundColor: Colors.black,
            // No AppBar for fullscreen video experience
            body: SafeArea(
              bottom: !_isFullScreen,
              child: Stack(
                children: [
                  // Video Player or Error Message
                  Center(
                    child: _hasError
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: Colors.red,
                                size: 48,
                              ),
                              SizedBox(height: 16),
                              Text(
                                _errorMessage,
                                style: TextStyle(color: Colors.white),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          )
                        : _isInitialized
                            ? Chewie(controller: _chewieController!)
                            : CircularProgressIndicator(
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.amber),
                              ),
                  ),

                  // Back button - hide in fullscreen mode
                  if (!_isFullScreen)
                    Positioned(
                      top: 16,
                      left: 16,
                      child: GestureDetector(
                        onTap: () => pop(),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.arrow_back, color: Colors.white),
                        ),
                      ),
                    ),

                  // Fullscreen toggle button
                  if (!_isFullScreen && _isInitialized)
                    Positioned(
                      top: 16,
                      right: 16,
                      child: GestureDetector(
                        onTap: _toggleFullScreen,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                          padding: EdgeInsets.all(8),
                          child: Icon(
                            Icons.fullscreen,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
