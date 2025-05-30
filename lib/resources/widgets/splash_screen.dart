import 'package:flutter/material.dart';
import '/resources/widgets/logo_widget.dart';
import 'dart:math';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  /// Create a new instance of the MaterialApp
  static MaterialApp app() {
    return MaterialApp(
      home: SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        // Updated the background color to #FFE635 with 15% opacity
        color: Color(0x26FFE635), // 0x26 represents 15% opacity
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Logo(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 50.0),
              child: AnimatedLoader(),
            ),
          ],
        ),
      ),
    );
  }
}

class AnimatedLoader extends StatefulWidget {
  final double size;
  final Color color;

  const AnimatedLoader({
    super.key,
    this.size = 50.0,
    this.color = Colors.white,
  });

  @override
  createState() => _AnimatedLoaderState();
}

class _AnimatedLoaderState extends State<AnimatedLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(
          milliseconds: 3000), // Increased duration for better visibility
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            _buildPulsatingCircle(),
            _buildRotatingDots(),
          ],
        );
      },
    );
  }

  Widget _buildPulsatingCircle() {
    return TweenAnimationBuilder(
      tween: Tween(begin: 0.8, end: 1.0),
      duration: const Duration(milliseconds: 1500),
      curve: Curves.easeInOut,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }

  Widget _buildRotatingDots() {
    return Transform.rotate(
      angle: _controller.value * 2 * pi,
      child: Stack(
        alignment: Alignment.center,
        children: List.generate(8, (index) {
          final double angle = (index / 8) * 2 * pi;
          final double offset = widget.size * 0.35;
          return Transform(
            transform: Matrix4.identity()
              ..translate(
                offset * cos(angle),
                offset * sin(angle),
              ),
            child: _buildDot(index),
          );
        }),
      ),
    );
  }

  Widget _buildDot(int index) {
    final double dotSize = widget.size * 0.1;
    final double scaleFactor =
        0.5 + (1 - _controller.value + index / 8) % 1 * 0.5;
    return Transform.scale(
      scale: scaleFactor,
      child: Container(
        width: dotSize,
        height: dotSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color,
        ),
      ),
    );
  }
}
