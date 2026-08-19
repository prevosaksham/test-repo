import 'uploaded_doc.dart';

/// Applicant / Co-Applicant captured details from `POST /application/details`
/// (`data.applicant` / `data.coApplicants` — now single objects, not arrays).
/// Missing/null fields parse to empty strings so the UI just shows blank.
class PersonDetail {
  const PersonDetail({
    required this.fullName,
    required this.fatherName,
    required this.address,
    required this.phoneNumber,
    required this.gender,
    required this.age,
    required this.dob,
    required this.aadhaarNumber,
    required this.panNumber,
    required this.dlNumber,
    required this.dlValidityDate,
    required this.dlIssueDate,
    required this.dlIssueRTO,
    required this.voterIdNumber,
    required this.residenceType,
    required this.ownerName,
    required this.consumerName,
    required this.billNumber,
    required this.maritalStatus,
    required this.relationship,
    required this.sameAsPermanent,
    required this.permanentAddress,
    required this.currAddress,
    required this.currCity,
    required this.currDistrict,
    required this.currState,
    required this.currPinCode,
    this.isConsentAccepted = false,
    this.panVerified = false,
    this.aadhaarVerified = false,
  });

  final String fullName;
  final String fatherName;
  final String address; // full address (as per Aadhar)
  final String phoneNumber;
  final String gender;
  final String age;
  final String dob; // date of birth (yyyy-MM-dd)
  final String aadhaarNumber;
  final String panNumber;
  final String dlNumber;
  final String dlValidityDate;
  final String dlIssueDate;
  final String dlIssueRTO;
  final String voterIdNumber;
  final String residenceType;
  final String ownerName; // owner of the residence (if not self-owned)
  final String consumerName; // bill consumer name → Owner Name on the No flow
  final String billNumber; // bill / reference number
  final String maritalStatus; // applicant only — lowercase key (married/…)
  final String relationship; // co-applicant only — lowercase key (husband/…)
  final bool sameAsPermanent;
  final String permanentAddress;
  final String currAddress;
  final String currCity;
  final String currDistrict;
  final String currState;
  final String currPinCode;
  final bool isConsentAccepted; // true → consent captured, false → not captured
  // Already verified on the server (`pan_verified` / `aadhar_verified`) → the
  // KYC screen marks the row Verified WITHOUT calling the verification API.
  final bool panVerified;
  final bool aadhaarVerified;

  String get ageLabel => age.isEmpty ? '' : '$age Years';

  /// Composed current address ("addr, city, district, state - pincode"), skipping
  /// the empty parts.
  String get currentAddress {
    final parts = [currAddress, currCity, currDistrict, currState]
        .where((e) => e.trim().isNotEmpty)
        .join(', ');
    final pin = currPinCode.trim();
    if (parts.isEmpty) return pin;
    return pin.isEmpty ? parts : '$parts - $pin';
  }

  // Which ID this person used: Aadhar when an aadhaarNumber is present, Voter
  // when a voterIdNumber is present (defaults to Aadhar).
  bool get hasAadhaar => aadhaarNumber.trim().isNotEmpty;
  bool get hasVoter => voterIdNumber.trim().isNotEmpty;
  String get idTypeLabel => (!hasAadhaar && hasVoter) ? 'Voter' : 'Aadhar';

  // The ID number row label + value follow the selected ID type.
  String get idNumberLabel =>
      (!hasAadhaar && hasVoter) ? 'Voter ID Number:' : 'Aadhar Number:';
  String get idNumber => hasAadhaar ? aadhaarNumber : voterIdNumber;

  // Permanent address: the API field when present; otherwise, when the current
  // address is the same as permanent, fall back to the ID (Aadhar/Voter)
  // address; else the separately-entered current address.
  String get permanentAddressDisplay {
    if (permanentAddress.trim().isNotEmpty) return permanentAddress;
    if (sameAsPermanent) return address;
    return currentAddress.isNotEmpty ? currentAddress : address;
  }

  // Current address: when it's the same as permanent, it IS the ID
  // (Aadhar/Voter) address; otherwise the separately-entered curr* fields.
  String get currentAddressDisplay {
    if (sameAsPermanent) return address;
    return currentAddress.isNotEmpty ? currentAddress : address;
  }

  factory PersonDetail.fromJson(Map<String, dynamic> j) {
    String s(String k) => j[k] == null ? '' : j[k].toString();
    // A server flag that may arrive as true / 1 / "true", under snake_case or
    // camelCase. Anything else (null, false, 0) → false.
    bool flag(List<String> keys) {
      for (final k in keys) {
        final v = j[k];
        if (v == null) continue;
        if (v == true || v == 1) return true;
        final t = v.toString().trim().toLowerCase();
        if (t == 'true' || t == '1') return true;
      }
      return false;
    }

    return PersonDetail(
      fullName: s('fullName'),
      fatherName: s('fatherName'),
      address: s('address'),
      phoneNumber: s('phoneNumber'),
      gender: s('gender'),
      age: s('age'),
      dob: s('dob'),
      aadhaarNumber: s('aadhaarNumber'),
      panNumber: s('panNumber'),
      dlNumber: s('dlNumber'),
      dlValidityDate: s('dlValidityDate'),
      dlIssueDate: s('dlIssueDate'),
      dlIssueRTO: s('dlIssueRTO'),
      voterIdNumber: s('voterIdNumber'),
      residenceType: s('residenceType'),
      ownerName: s('ownerName'),
      consumerName: s('consumerName'),
      // Bill / reference number — the API calls it `consumerNumber`
      // (falls back to `billNumber` if ever sent under that key).
      billNumber: j['consumerNumber'] != null ? s('consumerNumber') : s('billNumber'),
      maritalStatus: s('maritalStatus'),
      relationship: s('relationship'),
      sameAsPermanent: j['sameAsPermanent'] == true,
      permanentAddress: s('permanentAddress'),
      currAddress: s('currAddress'),
      currCity: s('currCity'),
      currDistrict: s('currDistrict'),
      currState: s('currState'),
      currPinCode: s('currPinCode'),
      isConsentAccepted: j['isConsentAccepted'] == true,
      panVerified: flag(const ['pan_verified', 'panVerified', 'isPanVerified']),
      aadhaarVerified: flag(const [
        'aadhar_verified',
        'aadhaar_verified',
        'aadharVerified',
        'aadhaarVerified',
        'isAadhaarVerified',
      ]),
    );
  }
}

/// A single value/displayName option for a dropdown (marital, relationship).
class Option {
  const Option({required this.value, required this.displayName});
  final String value;
  final String displayName;

  factory Option.fromJson(Map<String, dynamic> j) => Option(
        value: j['value'] == null ? '' : j['value'].toString(),
        // marital/relationship use `displayName`; addressType uses `display`.
        displayName: (j['displayName'] ?? j['display'] ?? '').toString(),
      );
}

/// Bank details from the application-details response (`data.bankDetails`).
/// `data.consents` — consent capture status + method per applicant.
class ConsentCapture {
  const ConsentCapture({required this.applicant, required this.coApplicant});
  final ConsentParty applicant;
  final ConsentParty coApplicant;

  factory ConsentCapture.fromJson(Map<String, dynamic> j) {
    Map<String, dynamic> m(dynamic v) =>
        v is Map ? Map<String, dynamic>.from(v) : const {};
    return ConsentCapture(
      applicant: ConsentParty.fromJson(m(j['applicant'])),
      coApplicant: ConsentParty.fromJson(m(j['coApplicant'])),
    );
  }

  /// Any party captured via the LINK method (vs OTP).
  bool get isLinkFlow => applicant.isLink || coApplicant.isLink;

  /// LINK-flow gate: applicant VERIFIED and (no co-applicant OR co VERIFIED).
  bool get allVerified =>
      applicant.isVerified && (!coApplicant.present || coApplicant.isVerified);
}

/// One party's consent capture
/// ({ status, isCaptured, capturedOn, mobileNumber, consentMethod }).
class ConsentParty {
  const ConsentParty({
    required this.status,
    required this.isCaptured,
    required this.capturedOn,
    required this.mobileNumber,
    required this.consentMethod,
  });
  final String status; // VERIFIED / DECLINED / PENDING
  final bool isCaptured;
  final String capturedOn; // yyyy-mm-dd
  final String mobileNumber;
  final String consentMethod; // LINK / OTP

  factory ConsentParty.fromJson(Map<String, dynamic> j) {
    String s(dynamic v) => v == null ? '' : v.toString();
    return ConsentParty(
      status: s(j['status']),
      isCaptured: j['isCaptured'] == true,
      capturedOn: s(j['capturedOn']),
      mobileNumber: s(j['mobileNumber']),
      consentMethod: s(j['consentMethod']),
    );
  }

  bool get isVerified => status.trim().toUpperCase() == 'VERIFIED';
  bool get isLink => consentMethod.trim().toUpperCase() == 'LINK';
  // This party is part of the flow (a real co-applicant, not an empty slot).
  bool get present =>
      mobileNumber.trim().isNotEmpty ||
      consentMethod.trim().isNotEmpty ||
      isCaptured;
}

class BankDetails {
  const BankDetails({
    required this.bankName,
    required this.accountHolderName,
    required this.branchName,
    required this.ifscCode,
    required this.accountType,
    required this.accountNumber,
    required this.isVerified,
  });

  final String bankName;
  final String accountHolderName;
  final String branchName;
  final String ifscCode;
  final String accountType;
  final String accountNumber;
  // Already verified on the server → skip the /bank-verification call.
  final bool isVerified;

  factory BankDetails.fromJson(Map<String, dynamic> j) {
    String s(String k) => j[k] == null ? '' : j[k].toString();
    final v = j['isVerified'];
    return BankDetails(
      bankName: s('bankName'),
      accountHolderName: s('accountHolderName'),
      branchName: s('branchName'),
      ifscCode: s('ifscCode'),
      accountType: s('accountType'),
      accountNumber: s('accountNumber'),
      isVerified: v == true || v == 1 || v?.toString().toLowerCase() == 'true',
    );
  }
}

/// One application stage from the details response (`data.stages[]`). Carries
/// the real `stageId` + `stageType` each flow screen must send to the backend
/// for its OWN stage (instead of forwarding the previous stage's id).
class ApplicationStage {
  const ApplicationStage({
    required this.stageId,
    required this.stageName,
    required this.stageType,
    required this.order,
    required this.isCompleted,
  });

  final String stageId;
  final String stageName;
  final String stageType; // e.g. "KYC"
  final String order;
  final bool isCompleted;

  factory ApplicationStage.fromJson(Map<String, dynamic> j) {
    String s(dynamic v) => v == null ? '' : v.toString();
    return ApplicationStage(
      stageId: s(j['stageId']),
      stageName: s(j['stageName']),
      stageType: s(j['stageType']),
      order: s(j['order']),
      isCompleted: j['isCompleted'] == true,
    );
  }
}

/// One document's verification status from `data.docsVerifications[]`.
class DocVerification {
  const DocVerification({
    required this.documentCode,
    required this.applicantType,
    required this.verificationStatus,
  });

  final String documentCode; // e.g. AADHAAR, CO_PAN, CURRENT_ADDRESS_PROOF
  final String applicantType; // APPLICANT / COAPPLICANT
  final String verificationStatus; // Pending / Failed / Success

  // Co-applicant when the type says so (COAPPLICANT / CO_APPLICANT) OR the
  // document code carries the CO_ prefix; everything else is the applicant.
  bool get isApplicant {
    final t = applicantType.toUpperCase().replaceAll('_', '');
    if (t == 'COAPPLICANT') return false;
    if (documentCode.trim().toUpperCase().startsWith('CO_')) return false;
    return true;
  }

  factory DocVerification.fromJson(Map<String, dynamic> j) {
    String s(dynamic v) => v == null ? '' : v.toString();
    return DocVerification(
      documentCode: s(j['documentCode']),
      applicantType: s(j['applicantType']),
      verificationStatus: s(j['verificationStatus']),
    );
  }
}

/// applicant + co-applicant details (+ bank details and dropdown options) from
/// the application-details response.
class ApplicationDetails {
  const ApplicationDetails({
    this.applicationId = '',
    this.applicationNo = '',
    this.createdAt = '',
    this.dealerName = '',
    this.status = '',
    this.kyc = '',
    this.isConsentAccepted = false,
    this.captureOn = '',
    this.applicantDocs = const [],
    this.coApplicantDocs = const [],
    this.docsVerifications = const [],
    this.applicant,
    this.coApplicant,
    this.applicantRaw,
    this.coApplicantRaw,
    this.bankDetails,
    this.applicantProof,
    this.coApplicantProof,
    this.maritalOptions = const [],
    this.relationshipOptions = const [],
    this.addressTypeOptions = const [],
    this.stages = const [],
    this.consents,
  });
  // The real application id + number (`data.application.id` / `.applicationNo`)
  // — the id the consent send-otp API expects (e.g. "56"), NOT the leadId.
  final String applicationId;
  final String applicationNo;
  final String createdAt; // application.createdAt (e.g. ISO timestamp; may be '')
  final String dealerName; // application.dealerName (empty until backend sends)
  final String status; // application.status (empty until backend sends)
  // application.kyc → KYC status (e.g. "COMPLETED"). Drives the Submit screen pill.
  final String kyc;
  // application.isConsentAccepted → drives the consent Status pill.
  final bool isConsentAccepted;
  // Consent capture date (data.captureOn / application.captureOn), e.g.
  // "2026-06-23". Empty until the backend sends it.
  final String captureOn;
  // All uploaded documents (data.applicantDocs[] / data.coApplicantDocs[]).
  final List<UploadedDoc> applicantDocs;
  final List<UploadedDoc> coApplicantDocs;
  // Per-document verification status (data.docsVerifications[]) — shown on KYC.
  final List<DocVerification> docsVerifications;
  final PersonDetail? applicant;
  final PersonDetail? coApplicant;
  // The full applicant / co-applicant objects exactly as received — sent back
  // (with the user's edits merged) on Proceed → save-applicant.
  final Map<String, dynamic>? applicantRaw;
  final Map<String, dynamic>? coApplicantRaw;
  final BankDetails? bankDetails;
  // Previously-uploaded Current Address proof (No flow) — from applicantDocs /
  // coApplicantDocs (documentCode CURRENT_ADDRESS_PROOF / CO_CURRENT_…).
  final UploadedDoc? applicantProof;
  final UploadedDoc? coApplicantProof;
  final List<Option> maritalOptions; // marital-status dropdown (applicant)
  final List<Option> relationshipOptions; // relation dropdown (co-applicant)
  final List<Option> addressTypeOptions; // Current Address Proof type dropdown
  final List<ApplicationStage> stages; // the flow's stages (data.stages[])
  // Per-applicant consent capture status + method (data.consents).
  final ConsentCapture? consents;

  /// The stage whose name matches [name] (case-insensitive), so a flow screen
  /// can send its OWN stageId/stageType. Null when the stage isn't present.
  ApplicationStage? stageByName(String name) {
    final n = name.trim().toLowerCase();
    for (final s in stages) {
      if (s.stageName.trim().toLowerCase() == n) return s;
    }
    return null;
  }

  factory ApplicationDetails.fromResponse(Map<String, dynamic> json) {
    final data = json['data'] is Map
        ? Map<String, dynamic>.from(json['data'] as Map)
        : json;
    // applicant / coApplicants are now single objects; tolerate the old array
    // shape (take the first item) for backward compatibility.
    PersonDetail? person(dynamic raw) {
      if (raw is Map) return PersonDetail.fromJson(Map<String, dynamic>.from(raw));
      if (raw is List && raw.isNotEmpty && raw.first is Map) {
        return PersonDetail.fromJson(Map<String, dynamic>.from(raw.first));
      }
      return null;
    }

    BankDetails? bank(dynamic raw) {
      if (raw is Map) return BankDetails.fromJson(Map<String, dynamic>.from(raw));
      if (raw is List && raw.isNotEmpty && raw.first is Map) {
        return BankDetails.fromJson(Map<String, dynamic>.from(raw.first));
      }
      return null;
    }

    List<Option> options(dynamic raw) => (raw is List ? raw : const [])
        .whereType<Map>()
        .map((e) => Option.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    // Keep the full person object exactly as received (object, or first item of
    // a legacy array) for the save-applicant payload.
    Map<String, dynamic>? raw(dynamic v) {
      if (v is Map) return Map<String, dynamic>.from(v);
      if (v is List && v.isNotEmpty && v.first is Map) {
        return Map<String, dynamic>.from(v.first);
      }
      return null;
    }

    // Previously-uploaded docs (applicantDocs + coApplicantDocs). Find the
    // current-address proof by its documentCode (searching both lists).
    final docs = <UploadedDoc>[];
    for (final r in [data['applicantDocs'], data['coApplicantDocs']]) {
      if (r is List) {
        docs.addAll(r.whereType<Map>().map(
            (e) => UploadedDoc.fromJson(Map<String, dynamic>.from(e))));
      }
    }
    UploadedDoc? byCode(String code) {
      for (final d in docs) {
        if (d.documentCode.toUpperCase() == code) return d;
      }
      return null;
    }

    // The application object (`data.application`) holds the real application id
    // + number used by downstream APIs (consent send-otp, etc.).
    final app = data['application'] is Map
        ? Map<String, dynamic>.from(data['application'] as Map)
        : const {};
    String appStr(String k) => app[k] == null ? '' : app[k].toString();

    // The dealer object (`data.dealer`) — holds the dealer name shown on the
    // Submit screen.
    final dealer = data['dealer'] is Map
        ? Map<String, dynamic>.from(data['dealer'] as Map)
        : const {};

    // The server key is `docsVerificationsDetails` (tolerate `docsVerifications`
    // / a nested application copy / top-level too).
    dynamic rawDocs = data['docsVerificationsDetails'] ??
        data['docsVerifications'] ??
        app['docsVerificationsDetails'] ??
        app['docsVerifications'] ??
        json['docsVerificationsDetails'] ??
        json['docsVerifications'];
    final docsVerifications = (rawDocs is List ? rawDocs : const [])
        .whereType<Map>()
        .map((e) => DocVerification.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    return ApplicationDetails(
      applicationId: appStr('id'),
      applicationNo: app['applicationNo'] != null
          ? appStr('applicationNo')
          : (app['applicationNumber'] != null
              ? appStr('applicationNumber')
              : appStr('applicationId')),
      // application.createdAt (fallback to a top-level createdAt). Empty until
      // the backend sends it.
      createdAt: app['createdAt'] != null
          ? appStr('createdAt')
          : (data['createdAt'] == null ? '' : data['createdAt'].toString()),
      // dealer.dealerName (fallback to application.dealerName / top-level).
      dealerName: dealer['dealerName'] != null
          ? dealer['dealerName'].toString()
          : (app['dealerName'] != null
              ? appStr('dealerName')
              : (data['dealerName'] == null
                  ? ''
                  : data['dealerName'].toString())),
      // application.status (fallback top-level). Empty until backend sends.
      status: app['status'] != null
          ? appStr('status')
          : (data['status'] == null ? '' : data['status'].toString()),
      // application.kyc → KYC status (e.g. "COMPLETED").
      kyc: appStr('kyc'),
      // application.isConsentAccepted → Status pill (Consent Captured / Not).
      isConsentAccepted: app['isConsentAccepted'] == true,
      // captureOn — from data, the application object, or top-level.
      captureOn: (data['captureOn'] ?? app['captureOn'] ?? json['captureOn'] ?? '')
          .toString(),
      applicantDocs: (data['applicantDocs'] is List
              ? data['applicantDocs'] as List
              : const [])
          .whereType<Map>()
          .map((e) => UploadedDoc.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      coApplicantDocs: (data['coApplicantDocs'] is List
              ? data['coApplicantDocs'] as List
              : const [])
          .whereType<Map>()
          .map((e) => UploadedDoc.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      docsVerifications: docsVerifications,
      applicant: person(data['applicant']),
      coApplicant: person(data['coApplicants']),
      applicantRaw: raw(data['applicant']),
      coApplicantRaw: raw(data['coApplicants']),
      bankDetails: bank(data['bankDetails']),
      applicantProof: byCode('CURRENT_ADDRESS_PROOF'),
      coApplicantProof: byCode('CO_CURRENT_ADDRESS_PROOF'),
      maritalOptions: options(data['marital']),
      relationshipOptions: options(data['relationship']),
      addressTypeOptions: options(data['addressType']),
      stages: (data['stages'] is List ? data['stages'] as List : const [])
          .whereType<Map>()
          .map((e) => ApplicationStage.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      consents: data['consents'] is Map
          ? ConsentCapture.fromJson(
              Map<String, dynamic>.from(data['consents'] as Map))
          : null,
    );
  }
}
