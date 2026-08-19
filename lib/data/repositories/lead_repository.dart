import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/api_response.dart';
import '../../core/network/network_info.dart';
import '../models/dealer.dart';
import '../models/financial_approval.dart';
import '../models/lead_basic_details.dart';
import '../models/lead_details.dart';
import '../models/lead_item.dart';
import '../models/lead_preview.dart';
import '../services/lead_api_service.dart';

/// Leads list use-case: connectivity check, API call, error mapping, parsing.
class LeadRepository {
  LeadRepository({LeadApiService? service, NetworkInfo? networkInfo})
      : _service = service ?? LeadApiService(),
        _network = networkInfo ?? NetworkInfo();

  final LeadApiService _service;
  final NetworkInfo _network;

  Future<void> _ensureOnline() async {
    if (!await _network.isConnected) {
      throw ApiException('No internet connection. Please check and try again.');
    }
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    await _ensureOnline();
    try {
      return await run();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Something went wrong. Please try again.');
    }
  }

  Future<LeadListPage> getLeads({
    required int page,
    int limit = 10,
    String search = '',
    String leadStatus = '', // '' = all; else the selected filter value
  }) {
    return _guard(() async {
      final json = await _service.list(
          page: page, limit: limit, search: search, leadStatus: leadStatus);
      return LeadListPage.fromJson(json,
          requestedPage: page, requestedLimit: limit);
    });
  }

  /// Status options for the My Leads filter (`GET /rm/rm-status`).
  Future<List<RmStatus>> getRmStatuses() {
    return _guard(() async {
      final res = await _service.rmStatus();
      final data = res is Map ? res['data'] : null;
      final list = data is List ? data : const [];
      return list
          .whereType<Map>()
          .map((e) => RmStatus.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    });
  }

  Future<LeadPreview> getPreview({required String leadId}) {
    return _guard(() async {
      final json = await _service.getPreview(leadId: leadId);
      return LeadPreview.fromJson(json);
    });
  }

  /// Financial / Loan Approval summary (`POST /rm/financial-approval`):
  /// approved loan details + generated docs. [leadId] arrives as a String —
  /// sent as an int when it parses (the API expects a number), else as-is.
  Future<FinancialApproval> getFinancialApproval({required String leadId}) {
    return _guard(() async {
      final json = await _service.financialApproval(
          applicationId: int.tryParse(leadId) ?? leadId);
      return FinancialApproval.fromResponse(json);
    });
  }

  /// Submit a Field Investigation (`POST /field-verification/create`).
  /// Returns the server's success message.
  Future<String> createFieldVerification({
    required Object applicationId,
    required double latitude,
    required double longitude,
    required String geoAddress,
    required String addressMatchStatus,
    required String status,
    required String remarks,
    required String reason,
    required String verificationDate,
    required Object stageId,
    required String stageType,
  }) {
    return _guard(() async {
      final body = await _service.createFieldVerification({
        'applicationId': applicationId,
        'latitude': latitude,
        'longitude': longitude,
        'geoAddress': geoAddress,
        'addressMatchStatus': addressMatchStatus,
        'status': status,
        'remarks': remarks,
        'reason': reason,
        'verificationDate': verificationDate,
        'stageId': stageId,
        'stageType': stageType,
      });
      return responseMessage(body,
          fallback: 'Field investigation submitted successfully');
    });
  }

  /// PDF bytes of a generated document — preview (view in-app).
  Future<Uint8List> previewDocument(
      {required String applicationId, required String documentType}) {
    return _guard(() => _service.pdfPreview(
        applicationId: int.tryParse(applicationId) ?? applicationId,
        documentType: documentType));
  }

  /// PDF bytes of a generated document — download (save to device).
  Future<Uint8List> downloadDocument(
      {required String applicationId, required String documentType}) {
    return _guard(() => _service.pdfDownload(
        applicationId: int.tryParse(applicationId) ?? applicationId,
        documentType: documentType));
  }

  /// PDF bytes fetched from a document's direct URL (generatedDocuments[].url).
  Future<Uint8List> documentBytesFromUrl(String url) {
    return _guard(() => _service.pdfFromUrl(url));
  }

  /// Read-only details for the My Leads → "View" screen
  /// (`POST /rm/lead-details`): header, timeline, applicant/co-applicant + docs.
  Future<LeadDetails> getLeadDetails({required String leadId}) {
    return _guard(() async {
      final json = await _service.leadDetails(leadId: leadId);
      return LeadDetails.fromResponse(json);
    });
  }

  /// Basic + vehicle details for the eye-icon "Lead Details" popup.
  Future<LeadBasicDetails> getLeadBasicDetails({required dynamic leadId}) {
    return _guard(() async {
      final json = await _service.leadBasicDetails(leadId: leadId);
      return LeadBasicDetails.fromResponse(json);
    });
  }

  /// Schedule a dealer visit (`POST /rm/scheduleVisit`). visitDate is date-only
  /// (YYYY-MM-DD), visitTime is 12-hour "hh:mm AM/PM". (No `notes` — the visit
  /// API doesn't support it.)
  /// Complete the Start-Application lead stage so the application stages unlock
  /// (`POST /rm/lead/preview` with { leadId, callId, visitId }). Returns the
  /// server's success message.
  Future<String> completeStartApplication({
    required String leadId,
    required String callId,
    required String visitId,
  }) {
    return _guard(() async {
      final body = await _service.completeStartApplication(body: {
        'leadId': leadId,
        'callId': callId,
        'visitId': visitId,
      });
      return responseMessage(body, fallback: 'Application started');
    });
  }

  /// Returns the server's success message (e.g. "Visit created successfully").
  Future<String> scheduleVisit({
    required String leadId,
    required String dealerId,
    required String visitDate,
    required String visitTime,
    required String visitStatus,
  }) {
    return _guard(() async {
      final body = await _service.scheduleVisit(body: {
        'leadId': leadId,
        'dealerId': dealerId,
        'visitTime': visitTime,
        'visitDate': visitDate,
        'visitStatus': visitStatus,
      });
      return responseMessage(body, fallback: 'Visit scheduled successfully');
    });
  }

  /// Dealers for the Visit step, filtered by the lead's OEM + city. [oemId] is
  /// sent as an int when it parses (the API expects a number), else as-is.
  ///
  /// The API filters strictly by city, so a city that doesn't exactly match the
  /// dealer records returns 0 dealers. When the city-filtered call comes back
  /// empty, we retry with just the OEM so the OEM's dealers still populate the
  /// dropdown instead of showing "No dealers found".
  Future<List<Dealer>> getDealers({
    required String oemId,
    required String city,
  }) {
    return _guard(() async {
      final oem = int.tryParse(oemId) ?? oemId;
      List<Dealer> parse(dynamic json) {
        final data = json['data'];
        if (data is! List) return <Dealer>[];
        final seen = <String>{};
        final out = <Dealer>[];
        for (final e in data.whereType<Map>()) {
          final d = Dealer.fromJson(Map<String, dynamic>.from(e));
          // A dealer with no id can't be a dropdown value; and duplicate ids
          // make DropdownButton assert. Skip both.
          if (d.id.trim().isEmpty || !seen.add(d.id)) continue;
          out.add(d);
        }
        return out;
      }

      var dealers = parse(await _service.getDealers(oemId: oem, city: city));
      // Fallback: city filter returned nothing → drop the city and try again.
      if (dealers.isEmpty && city.trim().isNotEmpty) {
        dealers = parse(await _service.getDealers(oemId: oem, city: ''));
      }
      return dealers;
    });
  }

  /// Record a call outcome (Call Received → INTERESTED / NOT_INTERESTED) or a
  /// requested callback (CALL_BACK_REQUESTED). `notes` is optional.
  /// Returns the server's success [message] and the resolved [callStatus] from
  /// the response `data` (e.g. "NOT_INTERESTED"), falling back to the value we
  /// sent when the API doesn't echo it.
  Future<({String message, String callStatus})> scheduleCall({
    required String leadId,
    required String callStatus,
    required String callDate,
    required String callTime,
    required bool followUpsRequired,
    String? notes,
    String? followUpsDate,
  }) {
    return _guard(() async {
      final body = await _service.scheduleCall(body: {
        'leadId': leadId,
        'callStatus': callStatus,
        'callDate': callDate,
        'callTime': callTime,
        'followUpsRequired': followUpsRequired,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        if (followUpsDate != null && followUpsDate.isNotEmpty)
          'followUpsDate': followUpsDate,
      });
      final data = body['data'];
      final resolvedStatus =
          (data is Map ? data['callStatus'] : null)?.toString() ?? callStatus;
      return (
        message: responseMessage(body, fallback: 'Call saved successfully'),
        callStatus: resolvedStatus,
      );
    });
  }
}
