import 'package:equatable/equatable.dart';

/// One option in the My Leads status filter (`GET /rm/rm-status` → `data[]`).
class RmStatus {
  const RmStatus({required this.value, required this.displayName});
  final String value; // e.g. "application_and_kyc"
  final String displayName; // e.g. "Application & KYC"

  factory RmStatus.fromJson(Map<String, dynamic> json) => RmStatus(
        value: (json['value'] ?? '').toString(),
        displayName:
            (json['display_name'] ?? json['displayName'] ?? '').toString(),
      );
}

/// Status chip data for a lead (value + label + hex colour from the API).
class LeadStatusInfo extends Equatable {
  const LeadStatusInfo({
    required this.value,
    required this.displayName,
    required this.colorHex,
  });

  final String value;
  final String displayName;
  final String colorHex; // e.g. "#FFC107"

  factory LeadStatusInfo.fromJson(Map<String, dynamic> json) {
    String s(dynamic v) => v == null ? '' : v.toString();
    return LeadStatusInfo(
      value: s(json['value']),
      displayName: s(json['displayName']),
      colorHex: s(json['color']),
    );
  }

  static const empty = LeadStatusInfo(value: '', displayName: '', colorHex: '');

  @override
  List<Object?> get props => [value, displayName, colorHex];
}

/// One lead row from `POST /rm/list` (`data[]`).
class LeadItem extends Equatable {
  const LeadItem({
    required this.id,
    required this.leadNo,
    required this.applicationNo,
    required this.name,
    required this.mobile,
    required this.email,
    required this.city,
    required this.state,
    required this.status,
    required this.agentName,
    required this.nextActivity,
    this.applicationId,
    this.isLoanApproved = false,
    this.isEsignDone = false,
    this.isFiDone = false,
    this.isPreDisbursementDone = false,
    this.isDisbursementQuestionsDone = false,
    this.isDisbursmentDone = false,
  });

  final String id;
  final String leadNo;
  final String applicationNo;
  // Numeric application PK (from the nested `application.id`) — required by
  // endpoints like /rm/financial-approval that key on the id, not the app-no.
  final int? applicationId;
  // Application stage flags from rm/list (isLoanApproved drives the current
  // Manage routing; isEsignDone / isDisbursmentDone parsed and available).
  final bool isLoanApproved;
  final bool isEsignDone;
  final bool isFiDone;
  // Pre-disbursal uploads completed (rm/list `isPredisdursementDone`).
  final bool isPreDisbursementDone;
  // Disbursement Validation questions answered (rm/list
  // `isDisbursementQuestionsDone`).
  final bool isDisbursementQuestionsDone;
  final bool isDisbursmentDone;
  final String name;
  final String mobile;
  final String email;
  final String city;
  final String state;
  final LeadStatusInfo status;
  final String agentName;
  final String nextActivity;

  /// "NAGPUR" + "MAHARASHTRA" -> "Nagpur, Maharashtra".
  String get location {
    String tc(String v) => v
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
    final c = tc(city);
    final s = tc(state);
    if (c.isEmpty) return s;
    if (s.isEmpty) return c;
    return '$c, $s';
  }

  factory LeadItem.fromJson(Map<String, dynamic> json) {
    String s(dynamic v) => v == null ? '' : v.toString();
    int? asInt(dynamic v) => v is int ? v : int.tryParse('${v ?? ''}');
    bool asBool(dynamic v) =>
        v == true || v == 1 || v?.toString().toLowerCase() == 'true';

    final statusJson = json['status'];
    final status = statusJson is Map
        ? LeadStatusInfo.fromJson(Map<String, dynamic>.from(statusJson))
        : LeadStatusInfo.empty;

    final agent = json['assignedAgent'];
    var agentName = '';
    if (agent is Map) {
      agentName = '${s(agent['firstName'])} ${s(agent['lastName'])}'.trim();
    }

    // `nextactivity` is now an object { value, stageAt } (current API) — show the
    // human-readable `stageAt` label (e.g. "Application & KYC"). Fall back to the
    // plain-string form for older responses.
    final naJson = json['nextactivity'];
    final nextActivity = naJson is Map
        ? s(naJson['stageAt'] ?? naJson['displayName'] ?? naJson['value'] ?? '')
        : s(naJson ?? '');

    // The rm/list row nests the application under an `application` object
    // (e.g. { application: { applicationNo / applicationNumber / id } }); fall
    // back to it when no flat application key is present.
    final appObj = json['application'] is Map
        ? Map<String, dynamic>.from(json['application'] as Map)
        : const <String, dynamic>{};

    return LeadItem(
      id: s(json['id']),
      leadNo: s(json['leadNo']),
      // API may key the application id differently across endpoints; accept the
      // common flat variants, then the nested `application` object, and leave
      // empty when the source doesn't send one.
      applicationNo: s(json['applicationNo'] ??
          json['applicationId'] ??
          json['applicationNumber'] ??
          json['appNo'] ??
          appObj['applicationNo'] ??
          appObj['applicationNumber'] ??
          appObj['id'] ??
          ''),
      name: s(json['name']),
      mobile: s(json['mobile']),
      email: s(json['email']),
      city: s(json['city']),
      state: s(json['state']),
      status: status,
      agentName: agentName,
      nextActivity: nextActivity,
      applicationId: asInt(appObj['id'] ?? json['applicationId']),
      // Accept the common flat / nested keys; defaults to false when absent.
      isLoanApproved: asBool(json['isLoanApproved'] ??
          json['loanApproved'] ??
          appObj['isLoanApproved'] ??
          appObj['loanApproved']),
      isEsignDone: asBool(json['isEsignDone'] ??
          json['esignDone'] ??
          appObj['isEsignDone'] ??
          appObj['esignDone']),
      isFiDone: asBool(json['isFiDone'] ??
          json['isFIDone'] ??
          json['fiDone'] ??
          appObj['isFiDone'] ??
          appObj['isFIDone'] ??
          appObj['fiDone']),
      // API key is `isPredisdursementDone`; accept a few sensible variants too.
      isPreDisbursementDone: asBool(json['isPredisdursementDone'] ??
          json['isPreDisbursementDone'] ??
          json['isPredisbursementDone'] ??
          appObj['isPredisdursementDone'] ??
          appObj['isPreDisbursementDone'] ??
          appObj['isPredisbursementDone']),
      isDisbursementQuestionsDone: asBool(
          json['isDisbursementQuestionsDone'] ??
              appObj['isDisbursementQuestionsDone']),
      isDisbursmentDone: asBool(json['isDisbursmentDone'] ??
          json['isDisbursementDone'] ??
          json['disbursmentDone'] ??
          appObj['isDisbursmentDone'] ??
          appObj['isDisbursementDone'] ??
          appObj['disbursmentDone']),
    );
  }

  @override
  List<Object?> get props => [
        id,
        leadNo,
        applicationNo,
        name,
        mobile,
        email,
        city,
        state,
        status,
        agentName,
        nextActivity,
        applicationId,
        isLoanApproved,
        isEsignDone,
        isFiDone,
        isPreDisbursementDone,
        isDisbursementQuestionsDone,
        isDisbursmentDone,
      ];
}

/// One page of leads + the pagination metadata (`summary` is intentionally
/// ignored — only `data` + paging are used).
class LeadListPage extends Equatable {
  const LeadListPage({
    required this.items,
    required this.pageNumber,
    required this.totalPages,
    required this.totalCount,
  });

  final List<LeadItem> items;
  final int pageNumber;
  final int totalPages;
  final int totalCount;

  factory LeadListPage.fromJson(Map<String, dynamic> json,
      {int requestedPage = 1, int requestedLimit = 10}) {
    int i(dynamic v, {int fb = 0}) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? fb;
      return fb;
    }

    // Current API nests `leads` + `pagination` under `data` (legacy had `data`
    // as the list with flat paging keys). `summary` is intentionally ignored.
    final data = json['data'];
    List rawLeads;
    Map<String, dynamic> pag;
    if (data is Map) {
      rawLeads = data['leads'] is List ? data['leads'] as List : const [];
      pag = data['pagination'] is Map
          ? Map<String, dynamic>.from(data['pagination'] as Map)
          : <String, dynamic>{};
    } else {
      rawLeads = data is List ? data : const [];
      pag = json; // legacy flat keys
    }

    final items = rawLeads
        .whereType<Map>()
        .map((e) => LeadItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    // Derive the real page count from the total record count (the API's
    // `totalPages` can over-report — e.g. claim 5 pages when page 5 is empty).
    // Fall back to the API value only when no usable count is available.
    final totalCount = i(pag['totalCount'] ?? pag['total_count']);
    final limit = i(
        pag['limit'] ??
            pag['pageSize'] ??
            pag['per_page'] ??
            pag['pageLimit'] ??
            pag['page_limit'],
        fb: requestedLimit);
    final apiPages = i(pag['totalPages'] ?? pag['total_pages'], fb: 1);
    final pageNumber =
        i(pag['pageNumber'] ?? pag['page_number'], fb: requestedPage);

    var totalPages = (totalCount > 0 && limit > 0)
        ? ((totalCount + limit - 1) ~/ limit)
        : apiPages;
    // Correct the count from the actual rows so empty pages never show: a short
    // page (< limit rows) is the last page; an empty page beyond the first means
    // the previous page was the last.
    if (items.isEmpty && pageNumber > 1) {
      totalPages = pageNumber - 1;
    } else if (limit > 0 && items.length < limit) {
      totalPages = pageNumber;
    }
    if (totalPages < 1) totalPages = 1;

    return LeadListPage(
      items: items,
      pageNumber: pageNumber,
      totalPages: totalPages,
      totalCount: totalCount,
    );
  }

  @override
  List<Object?> get props => [items, pageNumber, totalPages, totalCount];
}
