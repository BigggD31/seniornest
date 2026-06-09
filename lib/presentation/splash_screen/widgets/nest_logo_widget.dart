import 'package:flutter/material.dart';

class NestLogoWidget extends StatelessWidget {
  const NestLogoWidget({super.key, this.size = 110});

  final double size;

  static const String _logoAsset =
      'assets/images/Untitled_design-1774655836306.png';

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        _logoAsset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        semanticLabel: 'SeniorNest app logo',
        errorBuilder: (context, error, stackTrace) {
          return SizedBox(
            width: size,
            height: size,
            child: const Icon(Icons.home_rounded, color: Color(0xFF4A9B8E)),
          );
        },
      ),
    );
  }
}
