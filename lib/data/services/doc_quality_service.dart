import 'dart:convert';
import 'package:dio/dio.dart';

/// Calls Digio's id-card analyze API to check an uploaded document image.
/// This is a third-party service (separate base URL + Basic auth), so it uses
/// its own Dio instance rather than the app's [DioClient].
///
/// curl reference:
///   POST https://api.digio.in/v4/client/kyc/analyze/file/idcard
///   - multipart `front_part`        = the image file
///   - multipart `additional_request`= JSON (features / expected_ids /
///                                     additional_checks: BLUR + B&W)
class DocQualityService {
  DocQualityService({Dio? dio}) : _dio = dio ?? _build();

  static const String _baseUrl = 'https://api.digio.in';

  // Digio client Basic-auth token (client-id:secret, base64). Lives here for
  // now; move to secure config/env when one exists.
  static const String _authToken =
      'Basic QUNLMjQwOTA1MTQzMjEzMjg4NzcyWDhORldSQkVaTzM6QVBWRFVNVkhKRjhDRFpUV0tSNzhFT01GTzNCSUJOVU0=';

  static const String _analyzeIdCardPath = '/v4/client/kyc/analyze/file/idcard';

  static const List<String> _features = [
    'MASK',
    'CROP_ALIGN',
    'VERIFY',
    'SIGNATURE_EXTRACT',
    'FACE_EXTRACT',
    'SECURITY_FEATURE',
  ];

  final Dio _dio;

  static Dio _build() => Dio(BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
        validateStatus: (s) => s != null && s >= 200 && s < 300,
        headers: {
          'Accept': 'application/json',
          'Authorization': _authToken,
        },
      ));

  /// Upload [filePath] for analysis and return the raw decoded response.
  /// [expectedIds] tells Digio which id type(s) to expect for this slot
  /// (e.g. ["AADHAAR"], ["VOTER_ID"], ["PAN"], ["DRIVING_LICENSE"]).
  Future<Map<String, dynamic>> analyzeIdCard({
    required String filePath,
    required List<String> expectedIds,
    String? fileName,
  }) async {
    final additionalRequest = {
      'features': _features,
      'expected_ids': expectedIds,
      'additional_checks': ['BLUR_IMAGE', 'BLACK_AND_WHITE_IMAGE'],
    };
    final form = FormData.fromMap({
      'front_part': await MultipartFile.fromFile(filePath, filename: fileName),
      'additional_request': jsonEncode(additionalRequest),
    });
    final res = await _dio.post(_analyzeIdCardPath, data: form);
    final data = res.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String) {
      final decoded = jsonDecode(data);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    return <String, dynamic>{};
  }
}
