import 'package:flutter/services.dart';

/// Bridges the native download helper (Android, `MainActivity.kt`).
///
/// Saves a PDF into the device's public Downloads folder (visible in Files /
/// Downloads) and shows a "Download complete" status-bar notification that
/// opens the PDF on tap. Android-only.
class DownloadChannel {
  static const MethodChannel _channel = MethodChannel('eriksha/downloads');

  /// Returns the saved uri/path on success. Throws [PlatformException] on
  /// failure, or [MissingPluginException] on non-Android platforms.
  static Future<String?> savePdf({
    required String filename,
    required Uint8List bytes,
  }) {
    return _channel.invokeMethod<String>('savePdf', {
      'filename': filename,
      'bytes': bytes,
    });
  }
}
