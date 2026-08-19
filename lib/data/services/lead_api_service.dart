import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/api_response.dart';
import '../../core/network/dio_client.dart';

/// Wrapper around the paginated leads list (`POST /rm/list`).
class LeadApiService {
  LeadApiService({Dio? dio}) : _dio = dio ?? DioClient.instance.dio;

  final Dio _dio;

  Future<Map<String, dynamic>> list({
    required int page,
    required int limit,
    String search = '',
    String leadStatus = '', // '' = all; else the selected filter value
  }) async {
    final res = await _dio.post(ApiEndpoints.rmList, data: {
      'page_limit': limit.toString(),
      'page_number': page.toString(),
      'search': search,
      if (leadStatus.trim().isNotEmpty) 'leadStatus': leadStatus.trim(),
    });
    return unwrapResponse(res);
  }

  /// Lead status list for the filter (`GET /rm/rm-status`). Returns the raw
  /// response body ({ success, data: [...] }).
  Future<dynamic> rmStatus() async {
    final res = await _dio.get(ApiEndpoints.rmStatus);
    return res.data;
  }

  /// Resume/preview state for a single lead (`POST /rm/getPreview`).
  Future<Map<String, dynamic>> getPreview({required String leadId}) async {
    final res = await _dio.post(ApiEndpoints.rmGetPreview, data: {'leadId': leadId});
    return unwrapResponse(res);
  }

  /// Financial / Loan Approval summary for an application
  /// (`POST /rm/financial-approval`, body `{ applicationId }`).
  Future<Map<String, dynamic>> financialApproval(
      {required Object applicationId}) async {
    final res = await _dio.post(ApiEndpoints.rmFinancialApproval,
        data: {'leadId': applicationId});
    return unwrapResponse(res);
  }

  /// PDF bytes for a generated document — preview (`POST /pdf/preview`).
  Future<Uint8List> pdfPreview(
          {required Object applicationId, required String documentType}) =>
      _pdfBytes(ApiEndpoints.pdfPreview, applicationId, documentType);

  /// PDF bytes for a generated document — download (`POST /pdf/download`).
  Future<Uint8List> pdfDownload(
          {required Object applicationId, required String documentType}) =>
      _pdfBytes(ApiEndpoints.pdfDownload, applicationId, documentType);

  /// PDF bytes fetched directly from a document URL
  /// (`generatedDocuments[].url` from /field-verification/details). Handles a
  /// binary PDF body or a JSON envelope carrying a base64 PDF.
  Future<Uint8List> pdfFromUrl(String url) async {
    final res = await _dio.get(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    final data = res.data;
    final bytes = data is Uint8List
        ? data
        : (data is List<int> ? Uint8List.fromList(data) : null);
    if (bytes == null) throw ApiException('Could not read the document.');
    if (bytes.length >= 4 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46) {
      return bytes; // real PDF
    }
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      final b64 = _findBase64(decoded);
      if (b64 != null) return base64Decode(b64);
    } catch (_) {/* not JSON — fall through */}
    return bytes;
  }

  // Shared PDF fetch — requests raw bytes and returns the PDF. Handles both a
  // binary `application/pdf` body and a JSON body carrying a base64 string.
  Future<Uint8List> _pdfBytes(
      String path, Object applicationId, String documentType) async {
    final res = await _dio.post(
      path,
      data: {'applicationId': applicationId, 'documentType': documentType},
      options: Options(responseType: ResponseType.bytes),
    );
    final data = res.data;
    final bytes = data is Uint8List
        ? data
        : (data is List<int> ? Uint8List.fromList(data) : null);
    if (bytes == null) throw ApiException('Could not read the document.');
    // Real PDF? (magic bytes "%PDF")
    if (bytes.length >= 4 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46) {
      return bytes;
    }
    // Otherwise it may be a JSON envelope with a base64 PDF inside.
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      final b64 = _findBase64(decoded);
      if (b64 != null) return base64Decode(b64);
      if (decoded is Map && decoded['success'] == false) {
        throw ApiException(
            (decoded['message'] ?? 'Request failed.').toString());
      }
    } catch (e) {
      if (e is ApiException) rethrow;
    }
    return bytes; // fall back to whatever came back
  }

  // Depth-first search for a plausible base64 string under common keys.
  String? _findBase64(dynamic j) {
    if (j is Map) {
      for (final k in const [
        'data', 'base64', 'pdf', 'file', 'fileData', 'content',
        'pdfBase64', 'base64Data', 'base64String', 'document'
      ]) {
        final v = j[k];
        if (v is String && v.length > 100) return _stripDataUri(v);
      }
      for (final v in j.values) {
        final r = _findBase64(v);
        if (r != null) return r;
      }
    }
    return null;
  }

  String _stripDataUri(String s) {
    final i = s.indexOf('base64,');
    return i >= 0 ? s.substring(i + 7) : s;
  }

  /// Submit a Field Investigation (`POST /field-verification/create`).
  Future<Map<String, dynamic>> createFieldVerification(
      Map<String, dynamic> body) async {
    final res =
        await _dio.post(ApiEndpoints.fieldVerificationCreate, data: body);
    return unwrapResponse(res);
  }

  /// Read-only details for the View screen (`POST /rm/lead-details`).
  Future<Map<String, dynamic>> leadDetails({required String leadId}) async {
    final res =
        await _dio.post(ApiEndpoints.rmLeadDetails, data: {'leadId': leadId});
    return unwrapResponse(res);
  }

  /// Basic + vehicle details for the eye-icon popup
  /// (`POST /rm/lead-basic-details`, { leadId }).
  Future<Map<String, dynamic>> leadBasicDetails(
      {required dynamic leadId}) async {
    final res = await _dio
        .post(ApiEndpoints.rmLeadBasicDetails, data: {'leadId': leadId});
    return unwrapResponse(res);
  }

  /// Record a call outcome / schedule a callback (`POST /rm/scheduleCall`).
  Future<Map<String, dynamic>> scheduleCall({
    required Map<String, dynamic> body,
  }) async {
    final res = await _dio.post(ApiEndpoints.rmScheduleCall, data: body);
    return unwrapResponse(res);
  }

  /// Schedule / record a dealer visit (`POST /rm/scheduleVisit`).
  Future<Map<String, dynamic>> scheduleVisit({
    required Map<String, dynamic> body,
  }) async { 
    final res = await _dio.post(ApiEndpoints.rmScheduleVisit, data: body);
    return unwrapResponse(res);
  }

  /// Complete the Start-Application lead stage (`POST /rm/lead/preview`).
  /// Body: { leadId, callId, visitId }.
  Future<Map<String, dynamic>> completeStartApplication({
    required Map<String, dynamic> body,
  }) async {
    final res =
        await _dio.post(ApiEndpoints.rmCompleteStartApplication, data: body);
    return unwrapResponse(res);
  }

  /// Dealers for a lead's OEM + city (`POST /rm/getDealers`).
  Future<Map<String, dynamic>> getDealers({
    required Object oemId,
    required String city,
  }) async {
    final res = await _dio.post(
      ApiEndpoints.rmGetDealers,
      data: {'oemId': oemId, 'city': city},
    );
    return unwrapResponse(res);
  }
}
