import 'dart:convert';
import 'dart:typed_data';

/// Response model for `POST /field-verification/details`.
///
/// Shape (inside the envelope's `data`):
///   { loanApproved, applicantDetails, loanDetails, generatedDocuments[],
///     fieldVerifications[], allSigned }
class FinancialApproval {
  const FinancialApproval({
    required this.loanApproved,
    required this.applicant,
    required this.loan,
    required this.documents,
    required this.fieldVerification,
    required this.selfies,
    required this.addressMatchStatusOptions,
    required this.fvStatusOptions,
    required this.esignTitle,
    required this.esignDesc,
    required this.esignDate,
    required this.stages,
    required this.vehicleDocuments,
    required this.assetDetails,
    required this.allSigned,
    this.manualDocuments = const [],
    this.esignApplicantStatus = '',
    this.esignCoApplicantStatus = '',
    this.disbursementQuestions = const [],
    this.mnach,
  });

  final LoanApprovedInfo loanApproved;
  final ApplicantDetails applicant;
  final LoanDetails loan;
  final List<GeneratedDocument> documents;
  // The submitted Field Investigation (null until one is created). Carries the
  // visited geo-address, lat/long, chosen statuses, remarks/reason.
  final FieldVerification? fieldVerification;
  // Existing applicant / co-applicant FI selfies (with a viewable url).
  final Selfies selfies;
  // Dynamic option lists driving the FI form chips.
  final List<StatusOption> addressMatchStatusOptions;
  final List<StatusOption> fvStatusOptions;
  // eSign screen title/description (from `esignStatus`) + signed date.
  final String esignTitle;
  final String esignDesc;
  final String esignDate;
  // Current stage(s) — used to send stageId/stageType on FI submit.
  final List<Stage> stages;
  // Pre-disbursal vehicle documents keyed by pdc1/pdc2 (only uploaded ones).
  final Map<String, VehicleDoc> vehicleDocuments;
  // Vehicle/asset details (owner, manufacturer, chassis, engine, …).
  final AssetDetails? assetDetails;
  final bool allSigned;
  // Manually-uploaded signed documents (eSign Pending screen). Each entry is a
  // slot; `uploaded` is true once the RM has uploaded that document.
  final List<ManualDoc> manualDocuments;
  // eSign signer statuses (esign.applicant.status / esign.coApplicant.status) —
  // "SENT" once the eSign link has been sent to the signer.
  final String esignApplicantStatus;
  final String esignCoApplicantStatus;
  // Disbursement Validation questions (eSign Success screen) — each with the
  // question text, the saved Yes/No answer, and a checkpoint message.
  final List<DisbursementQuestion> disbursementQuestions;
  // Uploaded mNACH document (`data.mNACH`) — null until the RM uploads it.
  final ManualDoc? mnach;

  /// True once the eSign link has been sent (either signer's status = SENT) —
  /// used to show "eSign Link Sent" in place of the Initiate eSign button.
  bool get esignLinkSent =>
      esignApplicantStatus.trim().toUpperCase() == 'SENT' ||
      esignCoApplicantStatus.trim().toUpperCase() == 'SENT';

  /// The active stage (or the first) — drives the FI submit's stageId/stageType.
  Stage? get currentStage {
    for (final s in stages) {
      if (s.isActive) return s;
    }
    return stages.isNotEmpty ? stages.first : null;
  }

  /// Find a stage by its stage_key (e.g. PREDISBURSAL_UPLOADS) — needed when
  /// more than one stage is active and we want a specific one, not just the
  /// first active.
  Stage? stageByKey(String key) {
    for (final s in stages) {
      if (s.stageKey == key) return s;
    }
    return null;
  }

  /// Parse the FULL response body ({ success, data: {...} }) or a bare data map.
  factory FinancialApproval.fromResponse(Map<String, dynamic> json) {
    final data = json['data'] is Map
        ? Map<String, dynamic>.from(json['data'] as Map)
        : json;
    final docs = data['generatedDocuments'];
    // fieldVerifications can be null, an object, or (older) a list.
    final fvRaw = data['fieldVerifications'];
    final fvMap = fvRaw is Map
        ? Map<String, dynamic>.from(fvRaw)
        : (fvRaw is List && fvRaw.isNotEmpty && fvRaw.first is Map
            ? Map<String, dynamic>.from(fvRaw.first as Map)
            : null);
    return FinancialApproval(
      loanApproved: LoanApprovedInfo.fromJson(_map(data['loanApproved'])),
      applicant: ApplicantDetails.fromJson(_map(data['applicantDetails'])),
      loan: LoanDetails.fromJson(_map(data['loanDetails'])),
      documents: docs is List
          ? docs
              .whereType<Map>()
              .map((e) => GeneratedDocument.fromJson(
                  Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      fieldVerification:
          fvMap == null ? null : FieldVerification.fromJson(fvMap),
      selfies: Selfies.fromJson(_map(data['selfies'])),
      addressMatchStatusOptions:
          StatusOption.listFrom(data['addressMatchStatusOptions']),
      fvStatusOptions: StatusOption.listFrom(data['fvStatusOptions']),
      esignTitle: _s(_map(data['esignStatus'])['title']),
      esignDesc: _s(_map(data['esignStatus'])['desc']),
      // e-sign date + signed flag live under the nested `esign` object
      // (esign.esignDate / esign.esigned); fall back to the older top-level keys.
      esignDate: _s(_map(data['esign'])['esignDate'] ?? data['esignDate']),
      stages: data['stages'] is List
          ? (data['stages'] as List)
              .whereType<Map>()
              .map((e) => Stage.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      vehicleDocuments: _parseVehicleDocs(data['vehicleDocuments']),
      assetDetails: data['assetDetails'] is Map
          ? AssetDetails.fromJson(
              Map<String, dynamic>.from(data['assetDetails']))
          : null,
      // Signed = esign.esigned (true → done); fall back to legacy top-level.
      allSigned: _map(data['esign'])['esigned'] == true ||
          data['allSigned'] == true,
      // Signer statuses under esign.applicant / esign.coApplicant.
      esignApplicantStatus:
          _s(_map(_map(data['esign'])['applicant'])['status']),
      esignCoApplicantStatus:
          _s(_map(_map(data['esign'])['coApplicant'])['status']),
      // Disbursement Validation questions.
      disbursementQuestions: data['disbursementQuestions'] is List
          ? (data['disbursementQuestions'] as List)
              .whereType<Map>()
              .map((e) =>
                  DisbursementQuestion.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      // Uploaded mNACH document (single object under data.mNACH).
      mnach: data['mNACH'] is Map
          ? ManualDoc.fromJson(Map<String, dynamic>.from(data['mNACH']))
          : null,
      // Manually-uploaded signed documents (MANUAL_* slots).
      manualDocuments: data['manualDocuments'] is List
          ? (data['manualDocuments'] as List)
              .whereType<Map>()
              .map((e) => ManualDoc.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }
}

/// One manual signed-document slot from `data.manualDocuments[]` (eSign Pending
/// screen). [uploaded] is true once the RM has uploaded that document (the API
/// then fills in `id` / `url`).
class ManualDoc {
  const ManualDoc({
    required this.id,
    required this.documentCode,
    required this.name,
    required this.status,
    required this.generatedOnLabel,
    required this.url,
  });

  final String id;
  final String documentCode;
  final String name;
  final String status;
  final String generatedOnLabel;
  final String url;

  bool get uploaded => id.trim().isNotEmpty || url.trim().isNotEmpty;
  bool get hasHttpUrl => url.trim().startsWith('http');

  factory ManualDoc.fromJson(Map<String, dynamic> j) {
    String s(dynamic v) => v == null ? '' : v.toString();
    return ManualDoc(
      id: s(j['id']),
      documentCode: s(j['documentCode']),
      name: s(j['name']),
      status: s(j['status']),
      generatedOnLabel: s(j['generatedOnLabel']),
      url: s(j['url']),
    );
  }
}

/// One Disbursement Validation question (`data.disbursementQuestions[]`) — the
/// Yes/No question, its saved [answer] (null when unanswered) and the
/// [checkpoint] message shown in the rounded box below.
class DisbursementQuestion {
  const DisbursementQuestion({
    required this.key,
    required this.question,
    required this.answer,
    required this.checkpoint,
  });

  final String key;
  final String question;
  final bool? answer; // true = Yes, false = No, null = unanswered
  final String checkpoint;

  factory DisbursementQuestion.fromJson(Map<String, dynamic> j) {
    String s(dynamic v) => v == null ? '' : v.toString();
    final raw = j['answer'];
    final bool? ans = raw is bool
        ? raw
        : (raw == null ? null : raw.toString().toLowerCase() == 'true');
    return DisbursementQuestion(
      key: s(j['key']),
      question: s(j['question']),
      answer: ans,
      checkpoint: s(j['checkpoint']),
    );
  }
}

/// A { value, displayName } option (address-match / FV status).
class StatusOption {
  const StatusOption({required this.value, required this.displayName});
  final String value;
  final String displayName;

  factory StatusOption.fromJson(Map<String, dynamic> j) => StatusOption(
        value: _s(j['value']),
        displayName: _s(j['displayName']),
      );

  static List<StatusOption> listFrom(dynamic v) => v is List
      ? v
          .whereType<Map>()
          .map((e) => StatusOption.fromJson(Map<String, dynamic>.from(e)))
          .toList()
      : const [];
}

/// A workflow stage (snake_case) from the details response's `stages`.
class Stage {
  const Stage({
    required this.id,
    required this.stageKey,
    required this.stageName,
    required this.stageType,
    required this.order,
    required this.isActive,
  });
  final String id;
  final String stageKey; // e.g. FIELD_INVESTIGATION
  final String stageName;
  final String stageType; // e.g. APPLICATION
  final String order; // e.g. "6"
  final bool isActive;

  /// stageId to submit — the DB id when present, else the order number.
  String get stageId => id.isNotEmpty ? id : order;

  factory Stage.fromJson(Map<String, dynamic> j) => Stage(
        id: _s(j['id']),
        stageKey: _s(j['stage_key']),
        stageName: _s(j['stage_name']),
        stageType: _s(j['stage_type']),
        order: _s(j['order']),
        isActive: j['is_active'] == true,
      );
}

/// A pre-disbursal vehicle document (from `vehicleDocuments.pdcX`).
class VehicleDoc {
  const VehicleDoc(
      {required this.id, required this.documentCode, required this.thumbnail});
  final String id;
  final String documentCode;
  final String thumbnail; // base64 (data-URI or raw)

  Uint8List? get thumbnailBytes {
    final s = thumbnail.trim();
    if (s.isEmpty) return null;
    try {
      final comma = s.indexOf(',');
      return base64Decode(comma >= 0 ? s.substring(comma + 1) : s);
    } catch (_) {
      return null;
    }
  }

  /// The thumbnail as a network URL when the API sends one (new shape); '' when
  /// it's inline base64 (legacy) or empty — render [thumbnailBytes] then.
  String get thumbnailUrl {
    final t = thumbnail.trim();
    return t.startsWith('http') ? t : '';
  }

  factory VehicleDoc.fromJson(Map<String, dynamic> j) => VehicleDoc(
        id: _s(j['id']),
        documentCode: _s(j['documentCode']),
        thumbnail: _s(j['thumbnail']),
      );
}

/// Vehicle / asset details shown on the Pre-Disbursal screen.
class AssetDetails {
  const AssetDetails({
    required this.ownerName,
    required this.manufacturerName,
    required this.manufacturerDate,
    required this.modelNumber,
    required this.chassisNumber,
    required this.chassisStatus,
    required this.engineNumber,
  });
  final String ownerName;
  final String manufacturerName;
  final String manufacturerDate;
  final String modelNumber;
  final String chassisNumber;
  final String chassisStatus; // e.g. "New" — shown as a badge under the chassis
  final String engineNumber;

  factory AssetDetails.fromJson(Map<String, dynamic> j) => AssetDetails(
        ownerName: _s(j['ownerName']),
        manufacturerName: _s(j['manufacturerName']),
        manufacturerDate: _s(j['manufacturerDate']),
        modelNumber: _s(j['modelNumber']),
        chassisNumber: _s(j['chassisNumber']),
        chassisStatus: _s(j['chassisStatus']),
        engineNumber: _s(j['engineNumber']),
      );
}

Map<String, VehicleDoc> _parseVehicleDocs(dynamic v) {
  final out = <String, VehicleDoc>{};
  if (v is Map) {
    v.forEach((key, val) {
      if (val is Map) {
        out[key.toString()] =
            VehicleDoc.fromJson(Map<String, dynamic>.from(val));
      }
    });
  }
  return out;
}

/// A previously submitted Field Investigation (from `fieldVerifications`).
class FieldVerification {
  const FieldVerification({
    required this.id,
    required this.status,
    required this.addressMatchStatus,
    required this.geoAddress,
    required this.latitude,
    required this.longitude,
    required this.remarks,
    required this.reason,
    required this.verificationDate,
  });

  final String id;
  final StatusOption? status; // { value, displayName }
  final StatusOption? addressMatchStatus;
  final String geoAddress;
  final String latitude;
  final String longitude;
  final String remarks;
  final String reason;
  final String verificationDate;

  factory FieldVerification.fromJson(Map<String, dynamic> j) => FieldVerification(
        id: _s(j['id']),
        status: j['status'] is Map
            ? StatusOption.fromJson(Map<String, dynamic>.from(j['status']))
            : null,
        addressMatchStatus: j['addressMatchStatus'] is Map
            ? StatusOption.fromJson(
                Map<String, dynamic>.from(j['addressMatchStatus']))
            : null,
        geoAddress: _s(j['geoAddress']),
        latitude: _s(j['latitude']),
        longitude: _s(j['longitude']),
        remarks: _s(j['remarks']),
        reason: _s(j['reason']),
        verificationDate: _s(j['verificationDate']),
      );
}

/// Existing FI selfies for applicant + co-applicant.
class Selfies {
  const Selfies({required this.applicant, required this.coApplicant});
  final SelfieInfo? applicant;
  final SelfieInfo? coApplicant;

  factory Selfies.fromJson(Map<String, dynamic> j) => Selfies(
        applicant: SelfieInfo.tryFrom(j['applicant']),
        coApplicant: SelfieInfo.tryFrom(j['coApplicant']),
      );
}

class SelfieInfo {
  const SelfieInfo(
      {required this.id, required this.documentCode, required this.url});
  final String id;
  final String documentCode;
  final String url;

  bool get hasUrl => url.trim().isNotEmpty;

  static SelfieInfo? tryFrom(dynamic v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);
    return SelfieInfo(
      id: _s(m['id']),
      documentCode: _s(m['documentCode']),
      url: _s(m['url']),
    );
  }
}

class LoanApprovedInfo {
  const LoanApprovedInfo(
      {required this.status, required this.title, required this.message});
  final bool status;
  final String title;
  final String message;

  factory LoanApprovedInfo.fromJson(Map<String, dynamic> j) => LoanApprovedInfo(
        status: j['status'] == true,
        title: _s(j['title']),
        message: _s(j['message']),
      );
}

class ApplicantDetails {
  const ApplicantDetails({
    required this.id,
    required this.leadId,
    required this.applicationId,
    required this.applicantName,
    required this.mobileNumber,
    required this.pan,
    required this.dateTime,
    required this.address,
  });
  final String id;
  final String leadId;
  final String applicationId;
  final String applicantName;
  final String mobileNumber;
  final String pan;
  final String dateTime;
  final String address; // applicant's address (as per the application)

  factory ApplicantDetails.fromJson(Map<String, dynamic> j) => ApplicantDetails(
        id: _s(j['id']),
        leadId: _s(j['leadId']),
        applicationId: _s(j['applicationId']),
        applicantName: _s(j['applicantName']),
        mobileNumber: _s(j['mobileNumber']),
        pan: _s(j['pan']),
        dateTime: _s(j['dateTime']),
        address: _s(j['address']),
      );
}

class LoanDetails {
  const LoanDetails({
    required this.loanId,
    required this.oemDealer,
    required this.vehicleName,
    required this.vehicleCategory,
    required this.vehicleAmount,
    required this.loanAmount,
    required this.tenure,
    required this.rateOfInterest,
    required this.margin,
    required this.subsidy,
    required this.emiAmount,
  });
  final String loanId; // e.g. "LN00000045"
  final String oemDealer;
  final String vehicleName;
  final String vehicleCategory;
  final num? vehicleAmount;
  final num? loanAmount;
  final num? tenure;
  final num? rateOfInterest;
  final num? margin;
  final num? subsidy;
  final num? emiAmount;

  factory LoanDetails.fromJson(Map<String, dynamic> j) => LoanDetails(
        loanId: _s(j['loanId']),
        oemDealer: _s(j['oemDealer']),
        vehicleName: _s(j['vehicleName']),
        vehicleCategory: _s(j['vehicleCategory']),
        vehicleAmount: _n(j['vehicleAmount']),
        loanAmount: _n(j['loanAmount']),
        tenure: _n(j['tenure']),
        rateOfInterest: _n(j['rateOfInterest']),
        margin: _n(j['margin']),
        subsidy: _n(j['subsidy']),
        emiAmount: _n(j['emiAmount']),
      );
}

class GeneratedDocument {
  const GeneratedDocument({
    required this.documentCode,
    required this.name,
    required this.requiresEsign,
    required this.status,
    required this.generatedOnLabel,
    required this.canPreview,
    required this.canDownload,
    required this.fileData,
    required this.url,
  });
  final String documentCode;
  final String name;
  final bool requiresEsign;
  final String status; // e.g. "eSign Pending" / "Generated"
  final String generatedOnLabel;
  final bool canPreview;
  final bool canDownload;
  final String? fileData; // base64 / url when available
  final String url; // direct document url when the server provides one

  /// True once the document is signed/generated (not awaiting e-sign).
  bool get isSigned => status.toLowerCase() == 'generated' || !requiresEsign;

  /// The document delivered inline as base64 (the server sends the whole PDF in
  /// `url` as a `data:application/pdf;base64,…` URI, or in `fileData`). Decoded
  /// to bytes here so the UI shows it WITHOUT fetching the giant string as a URL
  /// (which would blow up into an HTTP 414 URI-Too-Long). Null when [url] is a
  /// real http link or there's nothing inline.
  Uint8List? get inlineBytes {
    final src = url.trim().isNotEmpty ? url.trim() : (fileData ?? '').trim();
    if (src.isEmpty || src.startsWith('http')) return null;
    final i = src.indexOf('base64,');
    final b64 = i >= 0 ? src.substring(i + 7) : src;
    try {
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  /// True when [url] is an actual http(s) link that can be fetched.
  bool get hasHttpUrl => url.trim().startsWith('http');

  /// Date-only form of [generatedOnLabel] — drops the ", HH:MM AM/PM" time
  /// (e.g. "01 July 2026, 09:26 AM" → "01 July 2026").
  String get generatedOnDateLabel {
    final i = generatedOnLabel.indexOf(',');
    return (i >= 0 ? generatedOnLabel.substring(0, i) : generatedOnLabel).trim();
  }

  factory GeneratedDocument.fromJson(Map<String, dynamic> j) =>
      GeneratedDocument(
        documentCode: _s(j['documentCode']),
        name: _s(j['name']),
        requiresEsign: j['requiresEsign'] == true,
        status: _s(j['status']),
        generatedOnLabel: _s(j['generatedOnLabel'] ?? j['generatedOn']),
        canPreview: j['canPreview'] == true,
        canDownload: j['canDownload'] == true,
        fileData: j['fileData']?.toString(),
        url: _s(j['url']),
      );
}

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
String _s(dynamic v) => v == null ? '' : v.toString();
num? _n(dynamic v) => v is num ? v : num.tryParse(v?.toString() ?? '');
