import 'package:flutter/material.dart';
import '../core/constants/app_assets.dart';

/// The SFL "Satin Finserv Limited" logo sitting inside a white circle, framed
/// by concentric translucent rings (the radial "pulse" seen in the mockups).
///
/// The logo is the [AppAssets.sflLogo] brand image — swap that single asset to
/// rebrand every screen that shows the logo.
class SflLogo extends StatelessWidget {
  const SflLogo({super.key, this.size = 220});

  /// Diameter of the outermost ring.
  final double size;

  @override
  Widget build(BuildContext context) {
    final double inner = size * 0.46; // white circle diameter

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _ring(size * 1.00, 0.06),
          _ring(size * 0.80, 0.09),
          _ring(size * 0.62, 0.13),
          Container(
            width: inner,
            height: inner,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0x1F000000),
                  blurRadius: 16,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            alignment: Alignment.center,
            // Wide wordmark: constrain the width so it sits inside the white
            // circle with a margin; height follows the logo's aspect ratio.
            child: Image.asset(
              AppAssets.sflLogo,
              width: inner * 0.76,
              fit: BoxFit.contain,
            ),
          ),
        ],
      ),
    );
  }

  Widget _ring(double d, double opacity) => Container(
        width: d,
        height: d,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: opacity),
        ),
      );
}
