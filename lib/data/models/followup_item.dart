import 'package:equatable/equatable.dart';
import 'lead_item.dart';

const _followupMonths = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// "2026-06-20" -> "20 June 2026"; falls back to the raw value, '' when empty.
String _fmtFollowupDate(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '';
  final d = DateTime.tryParse(raw.trim());
  if (d == null) return raw.trim();
  return '${d.day} ${_followupMonths[d.month - 1]} ${d.year}';
}

/// "17:00" / "16:09:00" -> "05:00 PM" / "04:09 PM". Falls back to the raw value.
String _fmtFollowupTime(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '';
  final bits = raw.trim().split(':');
  final h = int.tryParse(bits.first);
  if (h == null) return raw.trim();
  final m = bits.length > 1 ? (int.tryParse(bits[1]) ?? 0) : 0;
  final ampm = h < 12 ? 'AM' : 'PM';
  var h12 = h % 12;
  if (h12 == 0) h12 = 12;
  return '${h12.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} $ampm';
}

/// What kind of follow-up this is — drives which Home tab it lands in.
/// `call` -> "Call (Rescheduled)", `visit` -> "Scheduled Visits".
enum FollowupKind { call, visit, other }

/// One follow-up from `GET /followup/list` (`data[]`).
class FollowupItem extends Equatable {
  const FollowupItem({
    required this.id,
    required this.leadId,
    required this.leadNo,
    required this.leadName,
    required this.mobile,
    required this.kind,
    required this.status,
    required this.remarks,
    required this.dueDate,
    required this.time,
    this.leadStatus = '',
    this.dealerName = '',
  });

  final String id;
  final String leadId; // numeric lead id
  final String leadNo; // display Lead ID, e.g. "L00098"
  final String leadName; // "Bopan Bopn"
  final String mobile;
  final FollowupKind kind;
  final String status;
  final String remarks;
  final String? dueDate;
  final String? time;
  final String leadStatus; // nested lead's status, e.g. "call_rescheduled"
  final String dealerName; // visit dealer, e.g. "Alpha Motors"

  factory FollowupItem.fromJson(Map<String, dynamic> json) {
    String s(dynamic v) => v == null ? '' : v.toString();

    // followupType decides the tab; tolerate any case / stray values.
    final type = s(json['followupType']).toLowerCase().trim();
    final kind = type == 'call'
        ? FollowupKind.call
        : type == 'visit'
            ? FollowupKind.visit
            : FollowupKind.other;

    // DateTime? due;
    // final raw = json['dueDate'];
    // if (raw != null && raw.toString().isNotEmpty) {
    //   due = DateTime.tryParse(raw.toString());
    // }

    // Lead summary fields arrive at the TOP level (leadNo / firstName / lastName
    // / mobile / leadStatus). Fall back to a nested `lead` object for the legacy
    // shape so both responses work.
    final lead = json['lead'] is Map
        ? Map<String, dynamic>.from(json['lead'] as Map)
        : const <String, dynamic>{};
    String f(String key) {
      final top = s(json[key]);
      return top.isNotEmpty ? top : s(lead[key]);
    }
    final name = '${f('firstName')} ${f('lastName')}'.trim();

    return FollowupItem(
      id: s(json['id']),
      leadId: s(json['leadId']),
      leadNo: f('leadNo'),
      leadName: name,
      mobile: f('mobile'),
      kind: kind,
      status: s(json['followupStatus']),
      remarks: s(json['remarks']),
      dueDate: s(json['dueDate']),
      time: s(json['time']),
      leadStatus: f('leadStatus'),
      // dealerName arrives at the top level; tolerate a nested dealer object too.
      dealerName: s(json['dealerName']).isNotEmpty
          ? s(json['dealerName'])
          : (json['dealer'] is Map
              ? s((json['dealer'] as Map)['name'] ??
                  (json['dealer'] as Map)['dealerName'])
              : ''),
    );
  }

  bool get isCall => kind == FollowupKind.call;
  bool get isVisit => kind == FollowupKind.visit;

  /// Combined due date + time as "20 June 2026 05:00 PM". Builds from `dueDate`
  /// (yyyy-MM-dd) + `time` (24-hour "HH:mm" / "HH:mm:ss" → 12-hour AM/PM).
  /// Drops whichever part is missing; returns '' when both are empty.
  String get dateTimeLabel {
    final parts = [_fmtFollowupDate(dueDate), _fmtFollowupTime(time)]
        .where((s) => s.isNotEmpty);
    return parts.join(' ');
  }

  /// A minimal [LeadItem] for opening the lead's interaction screen from a
  /// follow-up card. Only the lead summary fields are known here (the list
  /// API doesn't return city/email/agent); the status chip uses the lead's
  /// status with the default colour.
  LeadItem toLeadItem() {
    String pretty(String v) => v
        .trim()
        .split(RegExp(r'[_\s]+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
    return LeadItem(
      id: leadId,
      leadNo: leadNo,
      applicationNo: '',
      name: leadName,
      mobile: mobile,
      email: '',
      city: '',
      state: '',
      status: LeadStatusInfo(
        value: leadStatus,
        displayName: pretty(leadStatus),
        colorHex: '',
      ),
      agentName: '',
      nextActivity: '',
    );
  }

  /// "03 Jun 2026 10:00 AM" in local time, or '—' when no due date.
  // String get dueDateLabel {
  //   final d = dueDate?.toLocal();
  //   if (d == null) return '—';
  //   const months = [
  //     'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  //     'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  //   ];
  //   final dd = d.day.toString().padLeft(2, '0');
  //   final mon = months[d.month - 1];
  //   var h = d.hour % 12;
  //   if (h == 0) h = 12;
  //   final hh = h.toString().padLeft(2, '0');
  //   final mm = d.minute.toString().padLeft(2, '0');
  //   final ampm = d.hour < 12 ? 'AM' : 'PM';
  //   return '$dd $mon ${d.year} $hh:$mm $ampm';
  // }

  @override
  List<Object?> get props => [
        id,
        leadId,
        leadNo,
        leadName,
        mobile,
        kind,
        status,
        remarks,
        dueDate,
        time,
        leadStatus,
        dealerName,
      ];
}
