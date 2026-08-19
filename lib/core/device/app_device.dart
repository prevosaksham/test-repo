import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

/// Device facts read once at startup.
///
/// Android 15+ enforces edge-to-edge, so the system navigation bar overlaps the
/// bottom of the app. We add an extra bottom gap on those versions so bottom
/// action buttons aren't hidden behind it (mirrors the GvVersions approach used
/// in the other app).
class AppDevice {
  AppDevice._();

  /// Android OS release version, e.g. 15 for Android 15. 0 on other platforms.
  static int androidRelease = 0;

  /// Read device info once. Call before runApp().
  static Future<void> init() async {
    if (!Platform.isAndroid) return;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      // version.release is the human OS version ("15", "14", "8.1.0" …).
      androidRelease = int.tryParse(info.version.release.split('.').first) ?? 0;
    } catch (_) {
      androidRelease = 0;
    }
  }

  /// Extra bottom gap (px) to clear the Android 15+ edge-to-edge nav bar.
  static double get bottomNavGap => androidRelease >= 15 ? 50 : 0;
}
