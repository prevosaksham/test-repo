import 'financial_approval.dart';
import 'lead_item.dart';
import 'person_detail.dart';
import 'uploaded_doc.dart';

/// One stage of the View screen's timeline (`data.timeline[]`). Carries only
/// what the API sends — name, description and the three status flags.
class LeadTimelineStage {
  const LeadTimelineStage({
    required this.id,
    required this.stageName,
    required this.desc,
    required this.actionAt,
    required this.completed,
    required this.current,
    required this.locked,
    required this.rejected,
    required this.completedByName,
  });

  final String id;
  final String stageName;
  final String desc; // details.desc — the action description
  final String actionAt; // details.actionAt — raw ISO timestamp (may be empty)
  final String completedByName; // details.completedBy.name (may be empty)
  final bool completed;
  final bool current;
  final bool locked;
  final bool rejected; // details.rejected — stage was rejected (shows a red ✕)

  // `rejected` wins over everything: a rejected stage is NEVER treated as
  // done/current/locked, so the other three flags are ignored when rejected.
  bool get isRejected => rejected;
  bool get isDone => !rejected && completed;
  bool get isCurrent => !rejected && !completed && current;
  bool get isLocked => !rejected && !completed && !current && locked;

  /// Short status label used on the pill (Rejected / Completed / In Progress /
  /// Locked / Pending).
  String get statusLabel {
    if (isRejected) return 'Rejected';
    if (isDone) return 'Completed';
    if (isCurrent) return 'In Progress';
    if (isLocked) return 'Locked';
    return 'Pending';
  }

  factory LeadTimelineStage.fromJson(Map<String, dynamic> j) {
    String s(dynamic v) => v == null ? '' : v.toString();
    // The action info is nested under `details` (null until the stage happens):
    // { desc, actionAt }. Fall back to a top-level `desc` for older responses.
    final det = j['details'] is Map
        ? Map<String, dynamic>.from(j['details'] as Map)
        : const <String, dynamic>{};
    // details.completedBy = { id, name } (null until the stage is actioned).
    final completedBy = det['completedBy'] is Map
        ? Map<String, dynamic>.from(det['completedBy'] as Map)
        : const <String, dynamic>{};
    return LeadTimelineStage(
      id: s(j['id']),
      stageName: s(j['stageName']),
      desc: s(det['desc'] ?? j['desc']),
      actionAt: s(det['actionAt']),
      completedByName: s(completedBy['name']),
      completed: j['completed'] == true,
      current: j['current'] == true,
      locked: j['locked'] == true,
      // `rejected` may sit on the stage root or inside `details`.
      rejected: j['rejected'] == true || det['rejected'] == true,
    );
  }
}

/// Full read-only payload behind the My Leads → "View" screen
/// (`POST /rm/lead-details` → `data`).
class LeadDetails {
  const LeadDetails({
    required this.name,
    required this.mobile,
    required this.location,
    required this.leadStatus,
    required this.currentStatus,
    required this.applicationId,
    required this.applicationNo,
    required this.applicationStatus,
    required this.timeline,
    required this.applicant,
    required this.coApplicant,
    required this.applicantDocs,
    required this.coApplicantDocs,
    this.bankDetails,
    this.applicationKycTitle = 'Application & KYC',
    this.loanApproval,
    this.documentsTitle = 'Documents',
    this.generatedDocuments = const [],
    this.fieldInvestigation,
    this.preDisbursal,
    this.postDisbursement,
  });

  // Header (data.lead + data.application).
  final String name;
  final String mobile;
  final String location;
  final LeadStatusInfo leadStatus;
  final String currentStatus; // data.lead.currentStatus (e.g. "IN_PROGRESS")
  final String applicationId; // data.application.id
  final String applicationNo; // data.application.applicationNo (may be empty)
  final String applicationStatus; // data.application.status (e.g. "draft")

  final List<LeadTimelineStage> timeline;

  // Application Details (data.applicationDetails).
  final PersonDetail? applicant;
  final PersonDetail? coApplicant;
  final List<UploadedDoc> applicantDocs;
  final List<UploadedDoc> coApplicantDocs;
  // Applicant's bank details (data.bankDetails) — shown on the Applicant tab.
  final BankDetails? bankDetails;
  // Accordion header title from data.applicationAndKyc.title (e.g.
  // "Application & KYC") — falls back to the default when the API omits it.
  final String applicationKycTitle;
  // Loan Approval section (applicationDetails.loanApproval) — null when the API
  // hasn't reached that stage.
  final LoanApproval? loanApproval;
  // Documents section (applicationDetails.documents) — title + generated PDFs
  // (Sanction Letter / Loan Agreement / KFS / Repayment Schedule).
  final String documentsTitle;
  final List<GeneratedDocument> generatedDocuments;
  // Field Investigation section (applicationDetails.fieldInvestigation).
  final FieldInvestigation? fieldInvestigation;
  // Pre-Disbursal Uploads section (applicationDetails.preDisbursal).
  final PreDisbursal? preDisbursal;
  // Post Disbursement section (applicationDetails.postDisbursement).
  final PostDisbursement? postDisbursement;

  /// Lead's current status nicely cased for display ("IN_PROGRESS" →
  /// "In Progress").
  String get currentStatusLabel {
    final s = currentStatus.replaceAll('_', ' ').trim();
    if (s.isEmpty) return '';
    return s
        .split(RegExp(r'\s+'))
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  /// Application status nicely cased for display ("draft" → "Draft").
  String get applicationStatusLabel {
    final s = applicationStatus.replaceAll('_', ' ').trim();
    if (s.isEmpty) return '';
    return s
        .split(RegExp(r'\s+'))
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  factory LeadDetails.fromResponse(Map<String, dynamic> json) {
    String s(dynamic v) => v == null ? '' : v.toString();

    final data = json['data'] is Map
        ? Map<String, dynamic>.from(json['data'] as Map)
        : json;

    final lead = data['lead'] is Map
        ? Map<String, dynamic>.from(data['lead'] as Map)
        : <String, dynamic>{};
    final app = data['application'] is Map
        ? Map<String, dynamic>.from(data['application'] as Map)
        : <String, dynamic>{};
    final ad = data['applicationDetails'] is Map
        ? Map<String, dynamic>.from(data['applicationDetails'] as Map)
        : <String, dynamic>{};
    // New shape: everything for this stage is nested under
    // `applicationDetails.applicationAndKyc` (with its own `title`,
    // applicationId/No/status, applicant/co + docs/bank). Accept it directly
    // under `data` too, just in case.
    final kyc = ad['applicationAndKyc'] is Map
        ? Map<String, dynamic>.from(ad['applicationAndKyc'] as Map)
        : (data['applicationAndKyc'] is Map
            ? Map<String, dynamic>.from(data['applicationAndKyc'] as Map)
            : <String, dynamic>{});
    // Documents section (applicationDetails.documents → { title, generated[] }).
    final docsSection = ad['documents'] is Map
        ? Map<String, dynamic>.from(ad['documents'] as Map)
        : (data['documents'] is Map
            ? Map<String, dynamic>.from(data['documents'] as Map)
            : <String, dynamic>{});

    final leadStatus = lead['leadStatus'] is Map
        ? LeadStatusInfo.fromJson(Map<String, dynamic>.from(lead['leadStatus']))
        : LeadStatusInfo.empty;

    final timeline = (data['timeline'] is List ? data['timeline'] as List : const [])
        .whereType<Map>()
        .map((e) => LeadTimelineStage.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    PersonDetail? person(dynamic raw) {
      if (raw is Map) {
        return PersonDetail.fromJson(Map<String, dynamic>.from(raw));
      }
      if (raw is List && raw.isNotEmpty && raw.first is Map) {
        return PersonDetail.fromJson(Map<String, dynamic>.from(raw.first));
      }
      return null;
    }

    List<UploadedDoc> docs(dynamic raw) => (raw is List ? raw : const [])
        .whereType<Map>()
        .map((e) => UploadedDoc.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    BankDetails? bank(dynamic raw) {
      if (raw is Map) return BankDetails.fromJson(Map<String, dynamic>.from(raw));
      if (raw is List && raw.isNotEmpty && raw.first is Map) {
        return BankDetails.fromJson(Map<String, dynamic>.from(raw.first));
      }
      return null;
    }

    return LeadDetails(
      name: s(lead['name']),
      mobile: s(lead['mobile']),
      location: s(lead['location']),
      leadStatus: leadStatus,
      currentStatus: s(lead['currentStatus']),
      applicationId:
          s(app['id']).isNotEmpty ? s(app['id']) : s(kyc['applicationId']),
      applicationNo: s(app['applicationNo']).isNotEmpty
          ? s(app['applicationNo'])
          : s(kyc['applicationNo']),
      applicationStatus: s(app['status']).isNotEmpty
          ? s(app['status'])
          : s(kyc['applicationStatus']),
      applicationKycTitle:
          s(kyc['title']).isNotEmpty ? s(kyc['title']) : 'Application & KYC',
      timeline: timeline,
      // Applicant / co-applicant + their docs may sit under `applicationDetails`
      // OR directly under `data` (depending on the endpoint shape) — accept both,
      // and tolerate the singular `coApplicant` key too.
      applicant: person(ad['applicant'] ?? data['applicant'] ?? kyc['applicant']),
      coApplicant: person(ad['coApplicants'] ??
          data['coApplicants'] ??
          ad['coApplicant'] ??
          data['coApplicant'] ??
          kyc['coApplicant'] ??
          kyc['coApplicants']),
      // Docs may be keyed `applicantDocuments`/`coApplicantDocuments` or the
      // shorter `applicantDocs`/`coApplicantDocs`, under `applicationDetails`,
      // `applicationAndKyc`, or directly under `data`.
      applicantDocs: docs(ad['applicantDocuments'] ??
          data['applicantDocuments'] ??
          ad['applicantDocs'] ??
          data['applicantDocs'] ??
          kyc['applicantDocuments']),
      coApplicantDocs: docs(ad['coApplicantDocuments'] ??
          data['coApplicantDocuments'] ??
          ad['coApplicantDocs'] ??
          data['coApplicantDocs'] ??
          kyc['coApplicantDocuments']),
      // bankDetails may sit under applicationDetails, applicationAndKyc, or data.
      bankDetails:
          bank(ad['bankDetails'] ?? data['bankDetails'] ?? kyc['bankDetails']),
      // Loan Approval section (applicationDetails.loanApproval).
      loanApproval: ad['loanApproval'] is Map
          ? LoanApproval.fromJson(Map<String, dynamic>.from(ad['loanApproval']))
          : (data['loanApproval'] is Map
              ? LoanApproval.fromJson(
                  Map<String, dynamic>.from(data['loanApproval']))
              : null),
      // Documents section (applicationDetails.documents.generated[]).
      documentsTitle:
          s(docsSection['title']).isNotEmpty ? s(docsSection['title']) : 'Documents',
      generatedDocuments: (docsSection['generated'] is List
              ? docsSection['generated'] as List
              : const [])
          .whereType<Map>()
          .map((e) => GeneratedDocument.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      // Field Investigation section (applicationDetails.fieldInvestigation).
      fieldInvestigation: ad['fieldInvestigation'] is Map
          ? FieldInvestigation.fromJson(
              Map<String, dynamic>.from(ad['fieldInvestigation']))
          : (data['fieldInvestigation'] is Map
              ? FieldInvestigation.fromJson(
                  Map<String, dynamic>.from(data['fieldInvestigation']))
              : null),
      // Pre-Disbursal Uploads section (applicationDetails.preDisbursal).
      preDisbursal: ad['preDisbursal'] is Map
          ? PreDisbursal.fromJson(Map<String, dynamic>.from(ad['preDisbursal']))
          : (data['preDisbursal'] is Map
              ? PreDisbursal.fromJson(
                  Map<String, dynamic>.from(data['preDisbursal']))
              : null),
      // Post Disbursement section (applicationDetails.postDisbursement).
      postDisbursement: ad['postDisbursement'] is Map
          ? PostDisbursement.fromJson(
              Map<String, dynamic>.from(ad['postDisbursement']))
          : (data['postDisbursement'] is Map
              ? PostDisbursement.fromJson(
                  Map<String, dynamic>.from(data['postDisbursement']))
              : null),
    );
  }
}

/// Loan Approval section (`applicationDetails.loanApproval`) — approved loan +
/// vehicle summary shown in its own accordion. Read-only; only what the API
/// sends is shown. Amounts/percentages/tenure arrive as strings.
class LoanApproval {
  const LoanApproval({
    required this.title,
    required this.applicantName,
    required this.mobileNumber,
    required this.panNumber,
    required this.dateTime,
    required this.oemDealer,
    required this.vehicleName,
    required this.vehicleCategory,
    required this.vehicleAmount,
    required this.subsidyPercentage,
    required this.loanAmount,
    required this.interestRate,
    required this.processingFee,
    required this.downpayment,
    required this.marginAmount,
    required this.tenure,
    required this.emi,
    required this.exShowroomPrice,
    required this.onRoadPrice,
    required this.insuranceAmount,
    required this.employmentType,
    required this.pdStatus,
    required this.pdDate,
    required this.pdRemarks,
  });

  final String title;
  final String applicantName;
  final String mobileNumber;
  final String panNumber;
  final String dateTime;
  final String oemDealer;
  final String vehicleName;
  final String vehicleCategory;
  final String vehicleAmount;
  final String subsidyPercentage;
  final String loanAmount;
  final String interestRate;
  final String processingFee;
  final String downpayment;
  final String marginAmount;
  final String tenure;
  final String emi;
  final String exShowroomPrice;
  final String onRoadPrice;
  final String insuranceAmount;
  final String employmentType;
  final String pdStatus;
  final String pdDate;
  final String pdRemarks;

  factory LoanApproval.fromJson(Map<String, dynamic> j) {
    String s(dynamic v) => v == null ? '' : v.toString();
    return LoanApproval(
      title: s(j['title']).isNotEmpty ? s(j['title']) : 'Loan Approval',
      applicantName: s(j['applicantName']),
      mobileNumber: s(j['mobileNumber']),
      panNumber: s(j['panNumber']),
      dateTime: s(j['dateTime']),
      oemDealer: s(j['oemDealer']),
      vehicleName: s(j['vehicleName']),
      vehicleCategory: s(j['vehicleCategory']),
      vehicleAmount: s(j['vehicleAmount']),
      subsidyPercentage: s(j['subsidyPercentage']),
      loanAmount: s(j['loanAmount']),
      interestRate: s(j['interestRate']),
      processingFee: s(j['processingFee']),
      downpayment: s(j['downpayment']),
      marginAmount: s(j['marginAmount']),
      tenure: s(j['tenure']),
      emi: s(j['emi']),
      exShowroomPrice: s(j['exShowroomPrice']),
      onRoadPrice: s(j['onRoadPrice']),
      insuranceAmount: s(j['insuranceAmount']),
      employmentType: s(j['employmentType']),
      pdStatus: s(j['pdStatus']),
      pdDate: s(j['pdDate']),
      pdRemarks: s(j['pdRemarks']),
    );
  }
}

/// Field Investigation section (`applicationDetails.fieldInvestigation`) — the
/// submitted FI verification (status, address-match, geo-location, remarks) plus
/// the FV selfie documents. Detail fields come from the nested `verifications`
/// object, falling back to the top-level fv/fi keys.
class FieldInvestigation {
  const FieldInvestigation({
    required this.title,
    required this.status,
    required this.addressMatchStatus,
    required this.geoAddress,
    required this.latitude,
    required this.longitude,
    required this.verificationDate,
    required this.remarks,
    required this.reason,
    required this.documents,
  });

  final String title;
  final String status;
  final String addressMatchStatus;
  final String geoAddress;
  final String latitude;
  final String longitude;
  final String verificationDate;
  final String remarks;
  final String reason;
  final List<UploadedDoc> documents; // FV selfies (applicant + co-applicant)

  factory FieldInvestigation.fromJson(Map<String, dynamic> j) {
    String s(dynamic v) => v == null ? '' : v.toString();
    final v = j['verifications'] is Map
        ? Map<String, dynamic>.from(j['verifications'] as Map)
        : <String, dynamic>{};
    final docs = (j['documents'] is List ? j['documents'] as List : const [])
        .whereType<Map>()
        .map((e) => UploadedDoc.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return FieldInvestigation(
      title:
          s(j['title']).isNotEmpty ? s(j['title']) : 'Field Investigation',
      status: s(v['status']).isNotEmpty
          ? s(v['status'])
          : s(j['fvStatus'] ?? j['fiStatus']),
      addressMatchStatus: s(v['addressMatchStatus']),
      geoAddress: s(v['geoAddress']),
      latitude: s(v['latitude']),
      longitude: s(v['longitude']),
      verificationDate: s(v['verificationDate']).isNotEmpty
          ? s(v['verificationDate'])
          : s(j['fvDate']),
      remarks:
          s(v['remarks']).isNotEmpty ? s(v['remarks']) : s(j['fvRemarks']),
      reason: s(v['reason']),
      documents: docs,
    );
  }
}

/// Pre-Disbursal Uploads section (`applicationDetails.preDisbursal`) — the
/// vehicle/asset summary plus the OCR-extracted vehicle documents (RTO Kit,
/// Invoice, PDCs, Insurance, …).
class PreDisbursal {
  const PreDisbursal({
    required this.title,
    required this.asset,
    required this.ocrData,
  });

  final String title;
  final VehicleAsset? asset;
  final List<OcrDoc> ocrData;

  factory PreDisbursal.fromJson(Map<String, dynamic> j) {
    String s(dynamic v) => v == null ? '' : v.toString();
    final ocr = (j['ocrData'] is List ? j['ocrData'] as List : const [])
        .whereType<Map>()
        .map((e) => OcrDoc.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return PreDisbursal(
      title:
          s(j['title']).isNotEmpty ? s(j['title']) : 'Predisbursal Uploads',
      asset: j['asset'] is Map
          ? VehicleAsset.fromJson(Map<String, dynamic>.from(j['asset']))
          : null,
      ocrData: ocr,
    );
  }
}

/// Vehicle / asset summary inside Pre-Disbursal (`preDisbursal.asset`).
class VehicleAsset {
  const VehicleAsset({
    required this.assetOwnerName,
    required this.modelNumber,
    required this.manufacturerName,
    required this.manufacturingDate,
    required this.chassisNumber,
    required this.motorSerialNumber,
    required this.vehicleModel,
    required this.vehicleType,
  });

  final String assetOwnerName;
  final String modelNumber;
  final String manufacturerName;
  final String manufacturingDate;
  final String chassisNumber;
  final String motorSerialNumber;
  final String vehicleModel;
  final String vehicleType;

  factory VehicleAsset.fromJson(Map<String, dynamic> j) {
    String s(dynamic v) => v == null ? '' : v.toString();
    return VehicleAsset(
      assetOwnerName: s(j['assetOwnerName']),
      modelNumber: s(j['modelNumber']),
      manufacturerName: s(j['manufacturerName']),
      manufacturingDate: s(j['manufacturingDate']),
      chassisNumber: s(j['chassisNumber']),
      motorSerialNumber: s(j['motorSerialNumber']),
      vehicleModel: s(j['vehicleModel']),
      vehicleType: s(j['vehicleType']),
    );
  }
}

/// One OCR-extracted vehicle document (`preDisbursal.ocrData[]`). [extractedData]
/// is kept raw so the UI can render whatever scalar fields the API returned;
/// [dataUri] is the PDF link when the source file is viewable.
class OcrDoc {
  const OcrDoc({
    required this.id,
    required this.documentCode,
    required this.verificationStatus,
    required this.ocrStatus,
    required this.dataUri,
    required this.extractedData,
  });

  final String id;
  final String documentCode;
  final String verificationStatus; // e.g. PENDING
  final String ocrStatus; // e.g. SUCCESS
  final String dataUri; // http PDF url ('' when none)
  final Map<String, dynamic> extractedData;

  bool get hasPdf => dataUri.trim().startsWith('http');

  factory OcrDoc.fromJson(Map<String, dynamic> j) {
    String s(dynamic v) => v == null ? '' : v.toString();
    return OcrDoc(
      id: s(j['id']),
      documentCode: s(j['documentCode']),
      verificationStatus: s(j['verificationStatus']),
      ocrStatus: s(j['OCRStatus'] ?? j['ocrStatus']),
      dataUri: s(j['dataUri']),
      extractedData: j['extractedData'] is Map
          ? Map<String, dynamic>.from(j['extractedData'] as Map)
          : <String, dynamic>{},
    );
  }
}

/// Post Disbursement section (`applicationDetails.postDisbursement`) — the NACH
/// mandate (when present) and post-disbursement documents (e.g. RC Book).
class PostDisbursement {
  const PostDisbursement({
    required this.title,
    required this.mandate,
    required this.documents,
  });

  final String title;
  final Map<String, dynamic>? mandate; // raw — rendered generically when present
  final List<UploadedDoc> documents;

  factory PostDisbursement.fromJson(Map<String, dynamic> j) {
    String s(dynamic v) => v == null ? '' : v.toString();
    final docs = (j['documents'] is List ? j['documents'] as List : const [])
        .whereType<Map>()
        .map((e) => UploadedDoc.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return PostDisbursement(
      title: s(j['title']).isNotEmpty ? s(j['title']) : 'Post Disbursement',
      mandate: j['mandate'] is Map
          ? Map<String, dynamic>.from(j['mandate'] as Map)
          : null,
      documents: docs,
    );
  }
}
