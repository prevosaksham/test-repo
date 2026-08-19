import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Renders an app icon asset — SVG or PNG — with an optional tint. Use this
/// everywhere instead of Image.asset/SvgPicture directly so swapping a PNG for
/// an SVG (or vice-versa) is just a path change in [AppAssets].
class AppIcon extends StatelessWidget {
  const AppIcon(this.asset, {super.key, this.size = 24, this.color});

  final String asset;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (asset.endsWith('.svg')) {
      return SvgPicture.asset(
        asset,
        width: size,
        height: size,
        colorFilter: color == null
            ? null
            : ColorFilter.mode(color!, BlendMode.srcIn),
      );
    }
    return Image.asset(asset, width: size, height: size, color: color);
  }
}
