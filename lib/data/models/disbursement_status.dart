/// Response of `POST /application/disbursement-status` ({ leadId }) — drives the
/// Disbursement Status page (Pending vs Success + summary).
class DisbursementStatus {
  const DisbursementStatus({
    required this.title,
    required this.subtitle,
    required this.isDisbursed,
    required this.summary,
    required this.loanAccountActivated,
    required this.canProceedToPostDisbursal,
    required this.stageId,
    required this.applicationId
  });

  final String title;
  final String subtitle;
  final bool isDisbursed;
  final DisbursementSummary summary;
  final bool loanAccountActivated;
  final bool canProceedToPostDisbursal;
  // Post-disbursal stage id — passed to the Post-Disbursal submit API.
  final String stageId;
  // Numeric application id (`data.id`) — sent as applicationId on submit.
  final String applicationId;

  factory DisbursementStatus.fromResponse(Map<String, dynamic> json) {
    final data = json['data'] is Map
        ? Map<String, dynamic>.from(json['data'] as Map)
        : const <String, dynamic>{};
    final summaryMap = data['disbursementSummary'] is Map
        ? Map<String, dynamic>.from(data['disbursementSummary'] as Map)
        : const <String, dynamic>{};
    String s(dynamic v) => v == null ? '' : v.toString();
    bool b(dynamic v) =>
        v == true || v == 1 || v?.toString().toLowerCase() == 'true';

    // stageId comes from data.stages[] — prefer the POST_DISBURSEMENT stage's
    // id, else the first stage. (Falls back to a flat stageId if ever sent.)
    String stageId = s(data['stageId'] ?? data['stage_id']);
    if (stageId.isEmpty && data['stages'] is List) {
      final stages = (data['stages'] as List).whereType<Map>().toList();
      Map? match;
      for (final e in stages) {
        if (e['stage_key']?.toString().toUpperCase() == 'POST_DISBURSEMENT') {
          match = e;
          break;
        }
      }
      match ??= stages.isNotEmpty ? stages.first : null;
      if (match != null) stageId = s(match['id']);
    }

    return DisbursementStatus(
      title: s(data['title']),
      subtitle: s(data['subtitle']),
      isDisbursed: b(data['isDisbursed']),
      summary: DisbursementSummary.fromJson(summaryMap),
      loanAccountActivated: b(data['loanAccountActivated']),
      canProceedToPostDisbursal: b(data['canProceedToPostDisbursal']),
      stageId: stageId,
      // Numeric application id → sent as applicationId on the submit call.
      applicationId: s(data['id'] ?? data['applicationId']),
    );
  }
}

/// `data.disbursementSummary` — the labelled rows shown in the summary card.
class DisbursementSummary {
  const DisbursementSummary({
    required this.applicationId,
    required this.applicationNo,
    required this.applicantName,
    required this.oemDealerName,
    required this.disbursementStatus,
    required this.loanId,
    required this.disbursementDateTime,
  });


  final String applicationId;
  final String applicationNo;
  final String applicantName;
  final String oemDealerName;
  final String disbursementStatus;
  final String loanId;
  final String disbursementDateTime;

  factory DisbursementSummary.fromJson(Map<String, dynamic> j) {
    String s(dynamic v) => v == null ? '' : v.toString();
    return DisbursementSummary(
      applicationId: s(j['applicationId']),
      applicationNo: s(j['applicationNo']),
      applicantName: s(j['applicantName']),
      oemDealerName: s(j['oemDealerName']),
      disbursementStatus: s(j['disbursementStatus']),
      loanId: s(j['loanId']),
      disbursementDateTime: s(j['disbursementDateTime']),
    );
  }
}
