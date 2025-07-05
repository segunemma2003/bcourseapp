import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'package:video_player/video_player.dart';

class HLSVideoPlayerScreen extends StatefulWidget {
  final VideoPlayerController controller;
  final String title;
  final bool isLocal;
  final String? hlsUrl;

  const HLSVideoPlayerScreen({
    required this.controller,
    required this.title,
    required this.isLocal,
    this.hlsUrl,
  });

  @override
  _HLSVideoPlayerScreenState createState() => _HLSVideoPlayerScreenState();
}

class _HLSVideoPlayerScreenState extends State<HLSVideoPlayerScreen> {
  bool _showControls = true;
  Timer? _controlsTimer;
  String _currentQuality = '240p';
  List<String> _availableQualities = ['240p', '360p', '480p', '720p', '1080p'];
  double _playbackSpeed = 1.0;
  List<double> _playbackSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
  bool _isBuffering = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    widget.controller.addListener(_videoListener);
    widget.controller.setPlaybackSpeed(_playbackSpeed);
    _hideControlsAfterDelay();
  }

  void _videoListener() {
    if (mounted) {
      final bool isBuffering = widget.controller.value.isBuffering;
      if (_isBuffering != isBuffering) {
        setState(() {
          _isBuffering = isBuffering;
        });
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_videoListener);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _controlsTimer?.cancel();
    super.dispose(); // Don't dispose controller here, parent will handle it
  }

  void _hideControlsAfterDelay() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _hideControlsAfterDelay();
    }
  }

  void _showQualitySelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      builder: (context) {
        return Container(
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                trans('Video Quality'),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 16),
              ...(_availableQualities.map((quality) => ListTile(
                    leading: Radio<String>(
                      value: quality,
                      groupValue: _currentQuality,
                      onChanged: widget.isLocal
                          ? null
                          : (value) {
                              Navigator.pop(context);
                              if (value != null) {
                                setState(() {
                                  _currentQuality = value;
                                });
                                // You can implement quality switching here
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(
                                          trans('Quality changed to $value'))),
                                );
                              }
                            },
                      activeColor: Colors.amber,
                    ),
                    title: Text(quality, style: TextStyle(color: Colors.white)),
                    subtitle: Text(
                      _getQualityDescription(quality),
                      style: TextStyle(color: Colors.grey),
                    ),
                  ))),
              if (widget.isLocal)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    trans(
                        'Quality selection not available for downloaded videos'),
                    style: TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showSpeedSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      builder: (context) {
        return Container(
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                trans('Playback Speed'),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 16),
              ...(_playbackSpeeds.map((speed) => ListTile(
                    leading: Radio<double>(
                      value: speed,
                      groupValue: _playbackSpeed,
                      onChanged: (value) {
                        Navigator.pop(context);
                        if (value != null) {
                          setState(() {
                            _playbackSpeed = value;
                          });
                          widget.controller.setPlaybackSpeed(value);
                        }
                      },
                      activeColor: Colors.amber,
                    ),
                    title: Text('${speed}x',
                        style: TextStyle(color: Colors.white)),
                  ))),
            ],
          ),
        );
      },
    );
  }

  String _getQualityDescription(String quality) {
    switch (quality) {
      case '240p':
        return trans('Data saver • Fast loading');
      case '360p':
        return trans('Low • Good for mobile data');
      case '480p':
        return trans('Medium • Balanced quality');
      case '720p':
        return trans('HD • High quality');
      case '1080p':
        return trans('Full HD • Best quality');
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          children: [
            // Video Player
            Center(
              child: AspectRatio(
                aspectRatio: widget.controller.value.aspectRatio,
                child: VideoPlayer(widget.controller),
              ),
            ),

            // Buffering Indicator
            if (_isBuffering)
              Center(
                child: Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                          color: Colors.amber, strokeWidth: 3),
                      SizedBox(height: 8),
                      Text(trans('Buffering...'),
                          style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
              ),

            // Custom Controls Overlay
            if (_showControls)
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.7),
                      Colors.transparent,
                      Colors.black.withOpacity(0.7),
                    ],
                  ),
                ),
                child: Column(
                  children: [
                    // Top Bar
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: Icon(Icons.arrow_back, color: Colors.white),
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.title,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // Quality indicator
                            GestureDetector(
                              onTap: _showQualitySelector,
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _currentQuality,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: 8),
                            IconButton(
                              onPressed: _showSpeedSelector,
                              icon: Icon(Icons.settings, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Spacer(),
                    // Bottom Controls
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          // Progress Bar
                          ValueListenableBuilder(
                            valueListenable: widget.controller,
                            builder: (context, VideoPlayerValue value, child) {
                              return Column(
                                children: [
                                  LinearProgressIndicator(
                                    value: value.duration.inMilliseconds > 0
                                        ? value.position.inMilliseconds /
                                            value.duration.inMilliseconds
                                        : 0,
                                    backgroundColor:
                                        Colors.white.withOpacity(0.3),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.amber),
                                  ),
                                  SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _formatDuration(value.position),
                                        style: TextStyle(
                                            color: Colors.white, fontSize: 12),
                                      ),
                                      Text(
                                        _formatDuration(value.duration),
                                        style: TextStyle(
                                            color: Colors.white, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            },
                          ),
                          SizedBox(height: 16),
                          // Play Controls
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                onPressed: () {
                                  final position =
                                      widget.controller.value.position;
                                  final newPosition =
                                      position - Duration(seconds: 10);
                                  widget.controller.seekTo(
                                    newPosition < Duration.zero
                                        ? Duration.zero
                                        : newPosition,
                                  );
                                },
                                icon: Icon(Icons.replay_10,
                                    color: Colors.white, size: 32),
                              ),
                              SizedBox(width: 20),
                              ValueListenableBuilder(
                                valueListenable: widget.controller,
                                builder:
                                    (context, VideoPlayerValue value, child) {
                                  return IconButton(
                                    onPressed: () {
                                      if (value.isPlaying) {
                                        widget.controller.pause();
                                      } else {
                                        widget.controller.play();
                                      }
                                      _hideControlsAfterDelay();
                                    },
                                    icon: Icon(
                                      value.isPlaying
                                          ? Icons.pause
                                          : Icons.play_arrow,
                                      color: Colors.white,
                                      size: 48,
                                    ),
                                  );
                                },
                              ),
                              SizedBox(width: 20),
                              IconButton(
                                onPressed: () {
                                  final position =
                                      widget.controller.value.position;
                                  final duration =
                                      widget.controller.value.duration;
                                  final newPosition =
                                      position + Duration(seconds: 10);
                                  widget.controller.seekTo(
                                    newPosition > duration
                                        ? duration
                                        : newPosition,
                                  );
                                },
                                icon: Icon(Icons.forward_10,
                                    color: Colors.white, size: 32),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }
}
