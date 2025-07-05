import 'dart:async';

import 'package:flutter/material.dart';

class AnimatedWatermarkWidget extends StatefulWidget {
  final String userName;

  const AnimatedWatermarkWidget({Key? key, required this.userName})
      : super(key: key);

  @override
  _AnimatedWatermarkWidgetState createState() =>
      _AnimatedWatermarkWidgetState();
}

class _AnimatedWatermarkWidgetState extends State<AnimatedWatermarkWidget>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Timer _timer;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: Duration(seconds: 2),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 0.8).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    // Show watermark every 5 minutes for 3 seconds
    _timer = Timer.periodic(Duration(minutes: 5), (timer) {
      _showWatermark();
    });
  }

  void _showWatermark() {
    _controller.forward().then((_) {
      Future.delayed(Duration(seconds: 3), () {
        if (mounted) {
          _controller.reverse();
        }
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _fadeAnimation,
      builder: (context, child) {
        return Opacity(
          opacity: _fadeAnimation.value,
          child: Center(
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Bhavani - ${widget.userName}',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
