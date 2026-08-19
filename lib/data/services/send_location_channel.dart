import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Result of a native send-location capture (see [SendLocationChannel]).
class SendLocationResult {
  const SendLocationResult({
    required this.success,
    required this.message,
    this.statusCode,
    this.id,
    this.code,
    this.latitude,
    this.longitude,
    this.address,
  });

  final bool success;
  final String message;
  final int? statusCode; // server status on success
  final String? id; // response.data.id on success
  final String? code; // LatLongErrorCode name on failure
  // What the SDK captured + sent (reverse-geocoded), returned on success.
  final double? latitude;
  final double? longitude;
  final String? address;

  static double? _toDouble(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

  factory SendLocationResult.fromMap(Map<dynamic, dynamic> m) =>
      SendLocationResult(
        success: m['success'] == true,
        message: (m['message'] ?? '').toString(),
        statusCode: m['statusCode'] is int ? m['statusCode'] as int : null,
        id: m['id']?.toString(),
        code: m['code']?.toString(),
        latitude: _toDouble(m['latitude']),
        longitude: _toDouble(m['longitude']),
        address: (m['address']?.toString().isNotEmpty ?? false)
            ? m['address'].toString()
            : null,
      );
}

/// Bridges the Surepass send-location SDK (Android-only, `MainActivity.kt`).
///
/// `captureLocation` requests location permission natively, then has the SDK
/// grab a location fix and post it — returning the server's response (or a
/// typed failure). iOS returns a not-supported failure.
class SendLocationChannel {
  static const MethodChannel _channel = MethodChannel('eriksha/sendlocation');

  static Future<SendLocationResult> captureLocation() async {
    try {
      final res =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('captureLocation');
      // Print exactly what the native SDK handed back.
      debugPrint('[SendLocation] SDK raw response → $res');
      if (res == null) {
        return const SendLocationResult(
            success: false, message: 'No response from location service.');
      }
      final result = SendLocationResult.fromMap(res);
      debugPrint('[SendLocation] parsed → success=${result.success} '
          'statusCode=${result.statusCode} id=${result.id} '
          'code=${result.code} message="${result.message}"');
      return result;
    } on MissingPluginException {
      // Not wired on this platform (e.g. iOS).
      return const SendLocationResult(
        success: false,
        message: 'Location capture is available on Android only.',
        code: 'UNSUPPORTED',
      );
    } on PlatformException catch (e) {
      return SendLocationResult(
        success: false,
        message: e.message ?? 'Could not capture location.',
        code: e.code,
      );
    }
  }
}
