import 'package:dio/dio.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/network_info.dart';
import '../models/consent_item.dart';
import '../models/disbursement_status.dart';
import '../models/person_detail.dart';
import '../models/rc_dl_details.dart';
import '../models/uploaded_doc.dart';
import '../services/application_api_service.dart';

/// Application document-upload use-case: connectivity check + error mapping.
class ApplicationRepository {
  ApplicationRepository({ApplicationApiService? service, NetworkInfo? networkInfo})
      : _service = service ?? ApplicationApiService(),
        _network = networkInfo ?? NetworkInfo();

  final ApplicationApiService _service;
  final NetworkInfo _network;

  /// Upload the KYC documents. [status] is 'draft' while filling, 'submited'
  /// on final application submit.
  /// Returns the parsed server response (so the caller can show the message).
  Future<dynamic> uploadDocuments({
    required String leadId,
    required String stageId,
    required String stageType,
    required String status,
    required Map<String, String?> filePaths,
  }) async {
    if (!await _network.isConnected) {
      throw ApiException('No internet connection. Please check and try again.');
    }
    try {
      return await _service.uploadDocuments(
        leadId: leadId,
        stageId: stageId,
        stageType: stageType,
        status: status,
        filePaths: filePaths,
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Something went wrong. Please try again.');
    }
  }

  /// Per-document upload: one single document, or one front+back pair, at a
  /// time. [files] maps each API field name to a local file path. Only the
  /// file(s) + leadId are sent.
  /// Returns the parsed server response (so the caller can show the per-document
  /// success message, e.g. "AADHAAR uploaded successfully").
  Future<dynamic> uploadFiles({
    required String leadId,
    required Map<String, String> files,
    Map<String, String>? fields, // extra non-file fields (e.g. proof_Type)
  }) async {
    if (!await _network.isConnected) {
      throw ApiException('No internet connection. Please check and try again.');
    }
    try {
      final result = await _service.uploadFiles(
          leadId: leadId, files: files, fields: fields);
      return result;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Something went wrong. Please try again.');
    }
  }

  /// House-ownership checksum (`POST /location/checksum`) → returns the parsed
  /// server response so the caller can read `data.applicant.ownership` /
  /// `data.coApplicant.ownership` (the derived Residence Type).
  Future<dynamic> checkOwnership({
    required Map<String, dynamic> applicant,
    required Map<String, dynamic> coApplicant,
  }) async {
    if (!await _network.isConnected) {
      throw ApiException('No internet connection. Please check and try again.');
    }
    try {
      return await _service.checkOwnership(
          applicant: applicant, coApplicant: coApplicant);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Something went wrong. Please try again.');
    }
  }

  /// Server-side RC verification (`POST /loan-application/verify`). Returns the
  /// raw server response so the caller can surface its success/error message;
  /// a non-2xx becomes an [ApiException] carrying the server's message.
  Future<dynamic> verifyLoanApplication({required int applicationId}) async {
    if (!await _network.isConnected) {
      throw ApiException('No internet connection. Please check and try again.');
    }
    try {
      return await _service.verifyLoanApplication(applicationId: applicationId);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Something went wrong. Please try again.');
    }
  }

  /// Initiate Aadhaar-linked eSign for all documents
  /// (`POST /application/esign/initiate-multi`). Returns the raw server response
  /// so the caller can surface its success/error message.
  Future<dynamic> initiateEsignMulti({required int applicationId}) async {
    if (!await _network.isConnected) {
      throw ApiException('No internet connection. Please check and try again.');
    }
    try {
      return await _service.initiateEsignMulti(applicationId: applicationId);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Something went wrong. Please try again.');
    }
  }

  /// Save the Disbursement Validation answers (`POST /loan-application/questions`).
  /// Returns the raw server response so the caller can gate navigation on success.
  Future<dynamic> saveLoanQuestions({
    required int applicationId,
    required int? stageId,
    required List<Map<String, dynamic>> questions,
  }) async {
    if (!await _network.isConnected) {
      throw ApiException('No internet connection. Please check and try again.');
    }
    try {
      return await _service.saveLoanQuestions(
          applicationId: applicationId, stageId: stageId, questions: questions);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Something went wrong. Please try again.');
    }
  }

  /// Complete a MANUAL e-sign (`POST /application/esign/manual`). Returns the raw
  /// server response so the caller can gate navigation on success.
  Future<dynamic> manualEsign({
    required int applicationId,
    required int stageId,
  }) async {
    if (!await _network.isConnected) {
      throw ApiException('No internet connection. Please check and try again.');
    }
    try {
      return await _service.manualEsign(
          applicationId: applicationId, stageId: stageId);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Something went wrong. Please try again.');
    }
  }

  /// RC Book + Driving License OCR details after verify
  /// (`POST /field-verification/rc-dl-details`).
  Future<RcDlDetails> rcDlDetails({required int applicationId}) async {
    if (!await _network.isConnected) {
      throw ApiException('No internet connection. Please check and try again.');
    }
    try {
      final res = await _service.rcDlDetails(applicationId: applicationId);
      return RcDlDetails.fromResponse(
          res is Map ? Map<String, dynamic>.from(res) : const {});
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Something went wrong. Please try again.');
    }
  }

  /// Applicant + co-applicant captured details (`POST /application/details`) for
  /// the Application Details step.
  Future<ApplicationDetails> getApplicationDetails({required String leadId}) async {
    if (!await _network.isConnected) {
      throw ApiException('No internet connection. Please check and try again.');
    }
    try {
      final res = await _service.getDetails(leadId: leadId);
      return ApplicationDetails.fromResponse(
        res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{},
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Something went wrong. Please try again.');
    }
  }

  /// Whether both applicants have accepted consent (`POST /consent/status`).
  /// Returns `data.isConsentAccepted`. Swallows transient errors → false, so a
  /// 5-second poll keeps running instead of throwing on a blip.
  Future<bool> getConsentAccepted({required dynamic applicationId}) async {
    if (!await _network.isConnected) return false;
    try {
      final res = await _service.consentStatus(applicationId: applicationId);
      final map = res is Map ? res : const {};
      final data = map['data'] is Map ? map['data'] as Map : const {};
      final v = data['isConsentAccepted'];
      return v == true || v == 1 || v?.toString().toLowerCase() == 'true';
    } catch (_) {
      return false; // transient — keep polling
    }
  }

  /// Disbursement status for the Disbursement Status page
  /// (`POST /application/disbursement-status`, { leadId }).
  Future<DisbursementStatus> getDisbursementStatus(
      {required dynamic leadId}) async {
    if (!await _network.isConnected) {
      throw ApiException('No internet connection. Please check and try again.');
    }
    try {
      final res = await _service.disbursementStatus(leadId: leadId);
      return DisbursementStatus.fromResponse(
        res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{},
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Something went wrong. Please try again.');
    }
  }

  /// Fetch the already-uploaded documents (applicant + co-applicant) so the
  /// Upload screen can re-show the images the user previously uploaded.
  Future<ApplicationDocs> getDocuments({required String leadId}) async {
    if (!await _network.isConnected) {
      throw ApiException('No internet connection. Please check and try again.');
    }
    try {
      final res = await _service.getDetails(leadId: leadId);
      return ApplicationDocs.fromDetails(
        res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{},
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Something went wrong. Please try again.');
    }
  }

  /// Consent/terms items for the consent screen (`POST /consent/list`,
  /// body { lang }), ordered by the API's `order`. [lang] is 'en' | 'hi' | 'mr'.
  Future<ConsentData> getConsentList({String lang = 'en'}) async {
    if (!await _network.isConnected) {
      throw ApiException('No internet connection. Please check and try again.');
    }
    try {
      final res = await _service.consentList(lang: lang);
      final map = res is Map ? Map<String, dynamic>.from(res) : const {};
      final data = map['data'];
      final list = data is List ? data : const [];
      final items = list
          .whereType<Map>()
          .map((e) => ConsentItem.fromJson(Map<String, dynamic>.from(e)))
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      return ConsentData(
        title: (map['title'] ?? '').toString(),
        description: (map['description'] ?? '').toString(),
        items: items,
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Something went wrong. Please try again.');
    }
  }

  /// Send consent OTP to the applicant + co-applicant (`POST /consent/send-otp`)
  /// on the consent screen's Send OTP. [consentIds] are all the consent item ids;
  /// the applicant/co-applicant mobile numbers become the applicantTypes list
  /// (an empty number is skipped).
  Future<dynamic> sendConsentOtp({
    required dynamic applicationId,
    required List<int> consentIds,
    required String applicantMobile,
    required String coApplicantMobile,
  }) async {
    if (!await _network.isConnected) {
      throw ApiException('No internet connection. Please check and try again.');
    }
    try {
      final applicantTypes = <Map<String, dynamic>>[
        if (applicantMobile.trim().isNotEmpty)
          {'applicantType': 'APPLICANT', 'mobileNumber': applicantMobile.trim()},
        if (coApplicantMobile.trim().isNotEmpty)
          {
            'applicantType': 'CO_APPLICANT',
            'mobileNumber': coApplicantMobile.trim()
          },
      ];
      return await _service.sendConsentOtp(
        applicationId: applicationId,
        consentIds: consentIds,
        applicantTypes: applicantTypes,
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Something went wrong. Please try again.');
    }
  }

  /// Send the consent LINK (`POST /consent/send-link`) to the applicant +
  /// co-applicant on the Application Details Proceed (Link mode). Same shape as
  /// [sendConsentOtp].
  Future<dynamic> sendConsentLink({
    required dynamic applicationId,
    required List<int> consentIds,
    required String applicantMobile,
    required String coApplicantMobile,
  }) async {
    if (!await _network.isConnected) {
      throw ApiException('No internet connection. Please check and try again.');
    }
    try {
      final applicantTypes = <Map<String, dynamic>>[
        if (applicantMobile.trim().isNotEmpty)
          {'applicantType': 'APPLICANT', 'mobileNumber': applicantMobile.trim()},
        if (coApplicantMobile.trim().isNotEmpty)
          {
            'applicantType': 'CO_APPLICANT',
            'mobileNumber': coApplicantMobile.trim()
          },
      ];
      return await _service.sendConsentLink(
        applicationId: applicationId,
        consentIds: consentIds,
        applicantTypes: applicantTypes,
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Something went wrong. Please try again.');
    }
  }

  /// Resend the OTP to a SINGLE applicant type (`POST /consent/resend-otp`).
  /// [applicantType] is "APPLICANT" or "CO_APPLICANT"; [mobileNumber] is that
  /// person's number.
  Future<dynamic> resendConsentOtp({
    required dynamic applicationId,
    required List<int> consentIds,
    required String applicantType,
    String mobileNumber = '',
  }) async {
    if (!await _network.isConnected) {
      throw ApiException('No internet connection. Please check and try again.');
    }
    try {
      return await _service.resendConsentOtp(
        applicationId: applicationId,
        consentIds: consentIds,
        applicantType: applicantType,
        mobileNumber: mobileNumber,
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Something went wrong. Please try again.');
    }
  }

  /// Resend the consent LINK to a SINGLE applicant type
  /// (`POST /consent/resend-link`). [applicantType] is "APPLICANT" or
  /// "CO_APPLICANT". Mirrors [resendConsentOtp] (no otp).
  Future<dynamic> resendConsentLink({
    required dynamic applicationId,
    required List<int> consentIds,
    required String applicantType,
    String mobileNumber = '',
  }) async {
    if (!await _network.isConnected) {
      throw ApiException('No internet connection. Please check and try again.');
    }
    try {
      return await _service.resendConsentLink(
        applicationId: applicationId,
        consentIds: consentIds,
        applicantType: applicantType,
        mobileNumber: mobileNumber,
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Something went wrong. Please try again.');
    }
  }

  /// Verify the applicant + co-applicant OTPs in ONE call
  /// (`POST /consent/verify-otp`). Each non-empty otp becomes an applicantTypes
  /// entry ({ applicantType, otp }).
  Future<dynamic> verifyConsentOtp({
    required dynamic applicationId,
    required String applicantOtp,
    String coApplicantOtp = '',
  }) async {
    if (!await _network.isConnected) {
      throw ApiException('No internet connection. Please check and try again.');
    }
    try {
      final applicantTypes = <Map<String, dynamic>>[
        if (applicantOtp.trim().isNotEmpty)
          {'applicantType': 'APPLICANT', 'otp': applicantOtp.trim()},
        if (coApplicantOtp.trim().isNotEmpty)
          {'applicantType': 'CO_APPLICANT', 'otp': coApplicantOtp.trim()},
      ];
      return await _service.verifyConsentOtp(
        applicationId: applicationId,
        applicantTypes: applicantTypes,
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Something went wrong. Please try again.');
    }
  }

  /// Save applicant + co-applicant details (`POST /application/save-applicant`)
  /// on the Application Details step's Proceed. [appData]/[coAppData] are the
  /// full person objects from /details merged with the user's edits.
  Future<dynamic> saveApplicant({
    required Map<String, dynamic> appData,
    required Map<String, dynamic> coAppData,
    required dynamic stageId,
    required String stageType,
    required String status,
    required dynamic leadId,
    required String consentType, // "OTP" / "LINK"
  }) async {
    if (!await _network.isConnected) {
      throw ApiException('No internet connection. Please check and try again.');
    }
    try {
      return await _service.saveApplicant(
        appData: appData,
        coAppData: coAppData,
        stageId: stageId,
        stageType: stageType,
        status: status,
        leadId: leadId,
        consentType: consentType,
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Something went wrong. Please try again.');
    }
  }

  /// Save the consent terms (`POST /application/save-term`) on the OTP Verified
  /// screen's Proceed.
  Future<dynamic> saveTerm({
    required dynamic applicationId,
    required dynamic leadId,
    required dynamic stageId,
    required String stageType,
  }) async {
    if (!await _network.isConnected) {
      throw ApiException('No internet connection. Please check and try again.');
    }
    try {
      return await _service.saveTerm(
        applicationId: applicationId,
        leadId: leadId,
        stageId: stageId,
        stageType: stageType,
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Something went wrong. Please try again.');
    }
  }

  /// Save KYC document verification (`POST /application/save-verification`) on
  /// the KYC screen's Proceed.
  Future<dynamic> saveVerification({
    required dynamic applicationId,
    required dynamic leadId,
    required dynamic stageId,
    required String stageType,
    required List<Map<String, dynamic>> docsVerifications,
  }) async {
    if (!await _network.isConnected) {
      throw ApiException('No internet connection. Please check and try again.');
    }
    try {
      return await _service.saveVerification(
        applicationId: applicationId,
        leadId: leadId,
        stageId: stageId,
        stageType: stageType,
        docsVerifications: docsVerifications,
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Something went wrong. Please try again.');
    }
  }

  /// Verify a bank account (`POST /bank-verification`) — the KYC screen's
  /// per-passbook Verify. [accountNumber]/[ifsc] come from /application/details
  /// `bankDetails`. Returns the parsed server response (caller checks success).
  Future<dynamic> verifyBank({
    required dynamic applicationId,
    required String accountNumber,
    required String ifsc,
  }) async {
    if (!await _network.isConnected) {
      throw ApiException('No internet connection. Please check and try again.');
    }
    try {
      return await _service.bankVerification(
          applicationId: applicationId, idNumber: accountNumber, ifsc: ifsc);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Something went wrong. Please try again.');
    }
  }

  /// PAN verification (`POST /application/pan-verification`) on the KYC screen's
  /// per-PAN Verify.
  Future<dynamic> verifyPan({
    required dynamic applicationId,
    required String applicantType,
    required String panNumber,
    required String fullName,
    required String dob,
  }) async {
    if (!await _network.isConnected) {
      throw ApiException('No internet connection. Please check and try again.');
    }
    try {
      return await _service.panVerification(
        applicationId: applicationId,
        applicantType: applicantType,
        idNumber: panNumber,
        fullName: fullName,
        dob: dob,
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Something went wrong. Please try again.');
    }
  }

  /// Aadhaar verification (`POST /application/aadhaar-verification`) on the KYC
  /// screen's per-Aadhaar Verify.
  Future<dynamic> verifyAadhaar({
    required dynamic applicationId,
    required String applicantType,
    required String aadhaarNumber,
  }) async {
    if (!await _network.isConnected) {
      throw ApiException('No internet connection. Please check and try again.');
    }
    try {
      return await _service.aadhaarVerification(
        applicationId: applicationId,
        applicantType: applicantType
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Something went wrong. Please try again.');
    }
  }

  /// Final application submit (`POST /application/submit`) on the Submit screen.
  Future<dynamic> submitApplication({
    required dynamic applicationId,
    required dynamic leadId,
    required dynamic stageId,
    required String stageType,
    required String status,
  }) async {
    if (!await _network.isConnected) {
      throw ApiException('No internet connection. Please check and try again.');
    }
    try {
      return await _service.submitApplication(
        applicationId: applicationId,
        leadId: leadId,
        stageId: stageId,
        stageType: stageType,
        status: status,
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Something went wrong. Please try again.');
    }
  }

  /// Pre-Disbursal submit (`POST /pre-disbursal/submit`, body
  /// { applicationId, stageId }). Returns the raw envelope.
  Future<dynamic> preDisbursalSubmit({
    required Object applicationId,
    required Object stageId,
  }) async {
    if (!await _network.isConnected) {
      throw ApiException('No internet connection. Please check and try again.');
    }
    try {
      return await _service.preDisbursalSubmit(
          applicationId: applicationId, stageId: stageId);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Something went wrong. Please try again.');
    }
  }

  /// Post-Disbursal submit (`POST /application/post-disbursement/submit`,
  /// body { applicationId, stageId }). Returns the raw envelope.
  Future<dynamic> postDisbursementSubmit({
    required Object applicationId,
    required Object stageId,
  }) async {
    if (!await _network.isConnected) {
      throw ApiException('No internet connection. Please check and try again.');
    }
    try {
      return await _service.postDisbursementSubmit(
          applicationId: applicationId, stageId: stageId);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Something went wrong. Please try again.');
    }
  }

  /// Fetch ONE previously-uploaded document's full file on demand
  /// (`POST /application/document`, body { documentId, applicantType }).
  /// [applicantType] is APPLICANT / CO_APPLICANT. The details list now carries
  /// only a small thumbnail, so the full image/PDF is loaded here when viewed.
  Future<DocumentFile> getDocumentFile({
    required String documentId,
    required String applicantType,
    String documentCode = '',
  }) async {
    if (!await _network.isConnected) {
      throw ApiException('No internet connection. Please check and try again.');
    }
    try {
      final res = await _service.getDocument(
        documentId: documentId,
        applicantType: applicantType,
        documentCode: documentCode,
      );
      return DocumentFile.fromResponse(
        res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{},
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Something went wrong. Please try again.');
    }
  }

  /// Delete an uploaded document by its grouped [docCode] (AADHAAR, CO_PAN…).
  /// Returns the parsed server response (caller checks `success`).
  Future<dynamic> deleteDocument({
    required String leadId,
    required String docCode,
  }) async {
    if (!await _network.isConnected) {
      throw ApiException('No internet connection. Please check and try again.');
    }
    try {
      return await _service.deleteDocument(leadId: leadId, docCode: docCode);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Something went wrong. Please try again.');
    }
  }
}
