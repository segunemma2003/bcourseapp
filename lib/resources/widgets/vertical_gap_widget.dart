import 'package:flutter/material.dart';

class VerticalGap extends StatelessWidget {
  final double? height;
  final double? width;
  const VerticalGap({super.key, this.height, this.width});

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: height ?? 4.0);
  }
}
