import 'package:dio/dio.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/network/dio_client.dart';

/// Multipart upload of KYC documents for the Upload Document stage
/// (`POST /application/upload-documents`). Uses the app's authenticated Dio
/// (Bearer token attached by the interceptor).
class ApplicationApiService {
  ApplicationApiService({Dio? dio}) : _dio = dio ?? DioClient.instance.dio;

  final Dio _dio;

  /// [filePaths] maps each API field name (e.g. AADHAAR_FRONT) to a local file
  /// path. Fields with a null/empty path are sent as an empty string (the
  /// backend expects every field present).
  Future<dynamic> uploadDocuments({
    required String leadId,
    required String stageId,
    required String stageType,
    required String status,
    required Map<String, String?> filePaths,
  }) async {
    final map = <String, dynamic>{
      'leadId': leadId,
      'stageId': stageId,
      'stageType': stageType,
      'status': status,
    };
    for (final entry in filePaths.entries) {
      final path = entry.value;
      if (path == null || path.isEmpty) {
        map[entry.key] = '';
      } else {
        map[entry.key] = await MultipartFile.fromFile(
          path,
          filename: path.split('/').last,
        );
      }
    }
    final res = await _dio.post(
      ApiEndpoints.applicationUploadDocuments,
      data: FormData.fromMap(map),
    );
    return res.data;
  }

  /// Per-document upload (`POST /application/upload`). Sends ONLY the given file
  /// field(s) + leadId — one single document, or one front+back pair. [files]
  /// maps each API field name (e.g. AADHAAR_FRONT) to a local file path.
  /// [files] maps each API field name to a local file path.
  Future<dynamic> uploadFiles({
    required String leadId,
    required Map<String, String> files,
    Map<String, String>? fields, // extra non-file form fields (e.g. proof_Type)
  }) async {
    final map = <String, dynamic>{'leadId': leadId};
    if (fields != null) map.addAll(fields);
    for (final entry in files.entries) {
      map[entry.key] = await MultipartFile.fromFile(
        entry.value,
        filename: entry.value.split('/').last,
      );
    }
    final res = await _dio.post(
      ApiEndpoints.applicationUpload,
      data: FormData.fromMap(map),
    );
    return res.data;
  }

  /// Consent/terms list shown on the consent screen (`POST /consent/list`,
  /// body { lang }). [lang] is the language code 'en' | 'hi' | 'mr'.
  Future<dynamic> consentList({String lang = 'en'}) async {
    final res = await _dio.post(ApiEndpoints.consentList, data: {'lang': lang});
    return res.data;
  }

  /// Server-side RC verification after the RC Book upload
  /// (`POST /loan-application/verify`, body { applicationId }).
  Future<dynamic> verifyLoanApplication({required int applicationId}) async {
    final res = await _dio.post(
      ApiEndpoints.loanApplicationVerify,
      data: {'applicationId': applicationId},
    );
    return res.data;
  }

  /// Initiate Aadhaar-linked eSign for all documents
  /// (`POST /application/esign/initiate-multi`, body { applicationId }).
  Future<dynamic> initiateEsignMulti({required int applicationId}) async {
    final res = await _dio.post(
      ApiEndpoints.applicationEsignInitiateMulti,
      data: {'applicationId': applicationId},
    );
    return res.data;
  }

  /// Save the Disbursement Validation answers (`POST /loan-application/questions`,
  /// body { applicationId, questions:[{ key, answer:bool }] }).
  Future<dynamic> saveLoanQuestions({
    required int applicationId,
    required int? stageId,
    required List<Map<String, dynamic>> questions,
  }) async {
    final res = await _dio.post(
      ApiEndpoints.loanApplicationQuestions,
      data: {
        'applicationId': applicationId,
        'stageId': stageId, // null (empty) for the eNACH flow
        'questions': questions,
      },
    );
    return res.data;
  }

  /// Complete a MANUAL e-sign (`POST /application/esign/manual`,
  /// body { applicationId, stageId }).
  Future<dynamic> manualEsign({
    required int applicationId,
    required int stageId,
  }) async {
    final res = await _dio.post(
      ApiEndpoints.applicationEsignManual,
      data: {'applicationId': applicationId, 'stageId': stageId},
    );
    return res.data;
  }

  /// RC Book + Driving License OCR details after verify
  /// (`POST /field-verification/rc-dl-details`, body { applicationId }).
  Future<dynamic> rcDlDetails({required int applicationId}) async {
    final res = await _dio.post(
      ApiEndpoints.fieldVerificationRcDlDetails,
      data: {'applicationId': applicationId},
    );
    return res.data;
  }

  /// Send consent OTP to the applicant + co-applicant (`POST /consent/send-otp`).
  /// [consentIds] are the int ids of every consent item; [applicantTypes] is the
  /// [{ applicantType, mobileNumber }] list for the applicant + co-applicant.
  Future<dynamic> sendConsentOtp({
    required dynamic applicationId,
    required List<int> consentIds,
    required List<Map<String, dynamic>> applicantTypes,
  }) async {
    final res = await _dio.post(
      ApiEndpoints.consentSendOtp,
      data: {
        'applicationId': applicationId,
        'consentIds': consentIds,
        'applicantTypes': applicantTypes,
      },
    );
    return res.data;
  }

  /// Send the consent LINK to the applicant + co-applicant
  /// (`POST /consent/send-link`). Same body shape as send-otp.
  Future<dynamic> sendConsentLink({
    required dynamic applicationId,
    required List<int> consentIds,
    required List<Map<String, dynamic>> applicantTypes,
  }) async {
    final res = await _dio.post(
      ApiEndpoints.consentSendLink,
      data: {
        'applicationId': applicationId,
        'consentIds': consentIds,
        'applicantTypes': applicantTypes,
      },
    );
    return res.data;
  }

  /// Resend the OTP to a SINGLE applicant type (`POST /consent/resend-otp`).
  /// [applicantType] is "APPLICANT" or "CO_APPLICANT"; [mobileNumber] is that
  /// person's number (sent only when non-empty).
  Future<dynamic> resendConsentOtp({
    required dynamic applicationId,
    required List<int> consentIds,
    required String applicantType,
    String mobileNumber = '',
  }) async {
    final res = await _dio.post(
      ApiEndpoints.consentResendOtp,
      data: {
        'applicationId': applicationId,
        'consentIds': consentIds,
        // Always sent (empty string when unavailable) — matches the resend-otp
        // body contract { applicationId, consentIds, mobileNumber, applicantType }.
        'mobileNumber': mobileNumber.trim(),
        'applicantType': applicantType,
      },
    );
    return res.data;
  }

  /// Resend the LINK to a SINGLE applicant type (`POST /consent/resend-link`).
  /// [applicantType] is "APPLICANT" or "CO_APPLICANT". Flat body — same shape
  /// as resend-otp: { applicationId, consentIds, mobileNumber, applicantType }.
  Future<dynamic> resendConsentLink({
    required dynamic applicationId,
    required List<int> consentIds,
    required String applicantType,
    String mobileNumber = '',
  }) async {
    final res = await _dio.post(
      ApiEndpoints.consentResendLink,
      data: {
        'applicationId': applicationId,
        'consentIds': consentIds,
        'mobileNumber': mobileNumber.trim(),
        'applicantType': applicantType,
      },
    );
    return res.data;
  }

  /// Verify the OTPs for the applicant + co-applicant in ONE call
  /// (`POST /consent/verify-otp`). [applicantTypes] is the
  /// [{ applicantType, otp }] list.
  Future<dynamic> verifyConsentOtp({
    required dynamic applicationId,
    required List<Map<String, dynamic>> applicantTypes,
  }) async {
    final res = await _dio.post(
      ApiEndpoints.consentVerifyOtp,
      data: {
        'applicationId': applicationId,
        'applicantTypes': applicantTypes,
      },
    );
    return res.data;
  }

  /// Full application details (`POST /application/details`, body { leadId }).
  /// Returns the parsed response; the caller reads `data.applicantDocs` /
  /// `data.coApplicantDocs` to re-show previously uploaded images.
  Future<dynamic> getDetails({required String leadId}) async {
    final res = await _dio.post(
      ApiEndpoints.applicationDetails,
      data: {'leadId': leadId},
    );
    return res.data;
  }

  /// Consent acceptance status (`POST /consent/status`, { applicationId }).
  Future<dynamic> consentStatus({required dynamic applicationId}) async {
    final res = await _dio.post(
      ApiEndpoints.consentStatus,
      data: {'applicationId': applicationId},
    );
    return res.data;
  }

  /// Disbursement status (`POST /application/disbursement-status`, { leadId }).
  Future<dynamic> disbursementStatus({required dynamic leadId}) async {
    final res = await _dio.post(
      ApiEndpoints.applicationDisbursementStatus,
      data: {'leadId': leadId},
    );
    return res.data;
  }

  /// Save applicant + co-applicant details (`POST /application/save-applicant`).
  /// [appData]/[coAppData] are the full person objects (from /details) with the
  /// user's edits merged in.
  Future<dynamic> saveApplicant({
    required Map<String, dynamic> appData,
    required Map<String, dynamic> coAppData,
    required dynamic stageId,
    required String stageType,
    required String status,
    required dynamic leadId,
    required String consentType, // "OTP" / "LINK" — outside app/coApp data
  }) async {
    final res = await _dio.post(
      ApiEndpoints.applicationSaveApplicant,
      data: {
        'appData': appData,
        'coAppData': coAppData,
        'stageId': stageId,
        'stageType': stageType,
        'status': status,
        'leadId': leadId,
        'consentType': consentType,
      },
    );
    return res.data;
  }

  /// Save the consent terms (`POST /application/save-term`) — on the OTP
  /// Verified screen's Proceed.
  Future<dynamic> saveTerm({
    required dynamic applicationId,
    required dynamic leadId,
    required dynamic stageId,
    required String stageType,
  }) async {
    final res = await _dio.post(
      ApiEndpoints.applicationSaveTerm,
      data: {
        'applicationId': applicationId,
        'leadId': leadId,
        'stageId': stageId,
        'stageType': stageType,
      },
    );
    return res.data;
  }

  /// Save KYC document verification (`POST /application/save-verification`) — on
  /// the KYC screen's Proceed. [docsVerifications] is the
  /// [{ applicantType, documentCode }] list.
  Future<dynamic> saveVerification({
    required dynamic applicationId,
    required dynamic leadId,
    required dynamic stageId,
    required String stageType,
    required List<Map<String, dynamic>> docsVerifications,
  }) async {
    final res = await _dio.post(
      ApiEndpoints.applicationSaveVerification,
      data: {
        'applicationId': applicationId,
        'leadId': leadId,
        'stageId': stageId,
        'stageType': stageType,
        'docsVerifications': docsVerifications,
      },
    );
    return res.data;
  }

  /// Final application submit (`POST /application/submit`) — on the Submit
  /// Application screen.
  Future<dynamic> submitApplication({
    required dynamic applicationId,
    required dynamic leadId,
    required dynamic stageId,
    required String stageType,
    required String status,
  }) async {
    final res = await _dio.post(
      ApiEndpoints.applicationSubmit,
      data: {
        'applicationId': applicationId,
        'leadId': leadId,
        'stageId': stageId,
        'stageType': stageType,
        'status': status,
      },
    );
    return res.data;
  }

  /// Pre-Disbursal submit (`POST /pre-disbursal/submit`, body
  /// { applicationId, stageId }).
  Future<dynamic> preDisbursalSubmit({
    required Object applicationId,
    required Object stageId,
  }) async {
    final res = await _dio.post(
      ApiEndpoints.predisbursal,
      data: {'applicationId': applicationId, 'stageId': stageId},
    );
    return res.data;
  }

  /// Post-Disbursal submit (`POST /application/post-disbursement/submit`,
  /// body { applicationId, stageId }).
  Future<dynamic> postDisbursementSubmit({
    required Object applicationId,
    required Object stageId,
  }) async {
    final res = await _dio.post(
      ApiEndpoints.postDisbursementSubmit,
      data: {'applicationId': applicationId, 'stageId': stageId},
    );
    return res.data;
  }

  /// Bank account verification (`POST /bank-verification`). [idNumber] is the
  /// applicant's bank account number, [ifsc] the IFSC code (both from
  /// /application/details `bankDetails`). `ifsc_details` is always true.
  Future<dynamic> bankVerification({
    required dynamic applicationId,
    required String idNumber,
    required String ifsc,
  }) async {
    final res = await _dio.post(
      ApiEndpoints.bankVerification,
      data: {
        'applicationId': applicationId,
        // 'id_number': idNumber,
        'ifsc': ifsc,
        'ifsc_details': true,
      },
    );
    return res.data;
  }

  /// PAN verification (`POST /application/pan-verification`). [idNumber] is that
  /// person's PAN, [fullName] their full name and [dob] their date of birth
  /// (yyyy-MM-dd) — all from /application/details. [applicantType] is
  /// APPLICANT / COAPPLICANT.
  Future<dynamic> panVerification({
    required dynamic applicationId,
    required String applicantType,
    required String idNumber,
    required String fullName,
    required String dob,
  }) async {
    final res = await _dio.post(
      ApiEndpoints.panVerification,
      data: {
        'applicationId': applicationId,
        'applicantType': applicantType,
        // 'id_number': idNumber,
        // 'full_name': fullName,
        // 'dob': _toIsoDate(dob),
      },
    );
    return res.data;
  }

  /// Normalises a date to the `yyyy-MM-dd` the verification API expects.
  /// Accepts `yyyy-MM-dd`, `dd-MM-yyyy`, either with `/` separators, and ISO
  /// datetimes (`yyyy-MM-ddTHH:mm:ss`). Anything else is passed through as-is.
  String _toIsoDate(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return v;
    // Drop any time component: "1982-01-26T00:00:00Z" / "1982-01-26 00:00:00".
    final datePart = v.split('T').first.split(' ').first;
    final parts = datePart.split(RegExp(r'[-/]'));
    if (parts.length != 3) return v;
    final a = parts[0], b = parts[1], c = parts[2];
    if (a.length == 4) return '$a-${_pad2(b)}-${_pad2(c)}'; // yyyy-MM-dd
    if (c.length == 4) return '$c-${_pad2(b)}-${_pad2(a)}'; // dd-MM-yyyy
    return v;
  }

  String _pad2(String s) => s.padLeft(2, '0');

  /// Aadhaar verification (`POST /application/aadhaar-verification`).
  /// [idNumber] is that person's Aadhaar number (from /application/details).
  /// [applicantType] is APPLICANT / COAPPLICANT.
  Future<dynamic> aadhaarVerification({
    required dynamic applicationId,
    required String applicantType,
  }) async {
    final res = await _dio.post(
      ApiEndpoints.aadhaarVerification,
      data: {
        'application_id': applicationId,
        'applicantType': applicantType,
        // 'id_number': idNumber,
      },
    );
    return res.data;
  }

  /// House-ownership checksum (`POST /location/checksum`) — derives the
  /// Residence Type for the applicant + co-applicant from their names.
  /// [applicant]/[coApplicant] are the request objects (fullName, fatherName /
  /// relationshipStatus, maritalStatus, permanentAddressProofName).
  Future<dynamic> checkOwnership({
    required Map<String, dynamic> applicant,
    required Map<String, dynamic> coApplicant,
  }) async {
    final res = await _dio.post(
      ApiEndpoints.locationChecksum,
      data: {
        'applicant': applicant,
        'coApplicant': coApplicant,
      },
    );
    return res.data;
  }

  /// Delete an uploaded document (`POST /application/delete-document`,
  /// body { leadId, docCode }). docCode is the grouped code (AADHAAR, CO_PAN…).
  Future<dynamic> deleteDocument({
    required String leadId,
    required String docCode,
  }) async {
    final res = await _dio.post(
      ApiEndpoints.applicationDeleteDocument,
      data: {'leadId': leadId, 'docCode': docCode},
    );
    return res.data;
  }

  /// Fetch ONE uploaded document's full file (`POST /application/document`,
  /// body { documentId, applicantType }). applicantType is APPLICANT /
  /// CO_APPLICANT. Returns the parsed response; the caller reads
  /// `data.fileData.dataUri`.
  Future<dynamic> getDocument({
    required String documentId,
    required String applicantType,
    String documentCode = '',
  }) async {
    final res = await _dio.post(
      ApiEndpoints.applicationDocument,
      data: {
        'documentId': int.tryParse(documentId) ?? documentId,
        'documentCode': documentCode,
        'applicantType': applicantType,
      },
    );
    return res.data;
  }
}
