import 'package:equatable/equatable.dart';

bool _b(dynamic v) => v == true || v == 'true' || v == 1 || v == '1';
int _i(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? 0;
}

String _s(dynamic v) => v == null ? '' : v.toString();

/// One step of a stepper (`leadStages` or `applicationStages`) from
/// `POST /rm/getPreview`. The flags drive the visual: completed → green tick,
/// current → active (where the RM resumes), locked → disabled/not clickable.
class StageItem extends Equatable {
  const StageItem({
    required this.id,
    required this.stageName,
    required this.stageType,
    required this.order,
    required this.completed,
    required this.current,
    required this.locked,
    this.desc = '',
  });

  final String id;
  final String stageName;
  final String stageType;
  final int order;
  final bool completed;
  final bool current;
  final bool locked;
  final String desc; // short description shown under the stage name

  factory StageItem.fromJson(Map<String, dynamic> json) => StageItem(
        id: _s(json['id']),
        stageName: _s(json['stageName']),
        stageType: _s(json['stageType']),
        order: _i(json['order']),
        completed: _b(json['completed']),
        current: _b(json['current']),
        locked: _b(json['locked']),
        desc: _s(json['desc']),
      );

  @override
  List<Object?> get props =>
      [id, stageName, stageType, order, completed, current, locked, desc];
}

/// Which actions the backend currently permits for this lead. Used only to
/// enable/disable the buttons inside each step (not the stepper itself).
class AllowedActions extends Equatable {
  const AllowedActions({
    this.canCall = false,
    this.canVisit = false,
    this.canPendingFollowup = false,
    this.canScheduleVisit = false,
    this.canCreateFollowup = false,
    this.canCompleteFollowup = false,
    this.canRescheduleFollowup = false,
    this.canStartApplication = false,
    this.canInteraction = false,
  });

  final bool canCall;
  final bool canVisit;
  final bool canPendingFollowup; // a callback is still pending for this lead
  final bool canScheduleVisit;
  final bool canCreateFollowup;
  final bool canCompleteFollowup;
  final bool canRescheduleFollowup;
  final bool canStartApplication;
  final bool canInteraction;

  factory AllowedActions.fromJson(Map<String, dynamic> json) => AllowedActions(
        canCall: _b(json['canCall']),
        canVisit: _b(json['canVisit']),
        canPendingFollowup: _b(json['canPendingFollowup']),
        canScheduleVisit: _b(json['canScheduleVisit']),
        canCreateFollowup: _b(json['canCreateFollowup']),
        canCompleteFollowup: _b(json['canCompleteFollowup']),
        canRescheduleFollowup: _b(json['canRescheduleFollowup']),
        canStartApplication: _b(json['canStartApplication']),
        canInteraction: _b(json['canInteraction']),
      );

  static const empty = AllowedActions();

  @override
  List<Object?> get props => [
        canCall,
        canVisit,
        canPendingFollowup,
        canScheduleVisit,
        canCreateFollowup,
        canCompleteFollowup,
        canRescheduleFollowup,
        canStartApplication,
        canInteraction,
      ];
}

/// The lead summary shown in the header card.
class PreviewLeadDetails extends Equatable {
  const PreviewLeadDetails({
    required this.id,
    required this.leadNo,
    required this.name,
    required this.mobile,
    required this.oemId,
    required this.leadStatus,
    required this.city,
    required this.state,
    this.statusDisplayName = '',
    this.statusColorHex = '',
  });

  final String id;
  final String leadNo;
  final String name;
  final String mobile;
  final String oemId;
  final String leadStatus; // status value, e.g. "call_rescheduled"
  final String city;
  final String state;
  final String statusDisplayName; // e.g. "APPLICATION STARTED"
  final String statusColorHex; // e.g. "#FF9800"

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

  factory PreviewLeadDetails.fromJson(Map<String, dynamic> json) {
    // leadStatus is now an object {value, displayName, color}; keep the value
    // (tolerate the older plain-string shape too).
    final ls = json['leadStatus'];
    final leadStatus = ls is Map ? _s(ls['value']) : _s(ls);
    return PreviewLeadDetails(
      id: _s(json['id']),
      leadNo: _s(json['leadNo']),
      name: _s(json['name']),
      mobile: _s(json['mobile']),
      oemId: _s(json['oemId']),
      leadStatus: leadStatus,
      city: _s(json['city']),
      state: _s(json['state']),
      statusDisplayName: ls is Map ? _s(ls['displayName']) : '',
      statusColorHex: ls is Map ? _s(ls['color']) : '',
    );
  }

  static const empty = PreviewLeadDetails(
    id: '',
    leadNo: '',
    name: '',
    mobile: '',
    oemId: '',
    leadStatus: '',
    city: '',
    state: '',
  );

  @override
  List<Object?> get props => [
        id,
        leadNo,
        name,
        mobile,
        oemId,
        leadStatus,
        city,
        state,
        statusDisplayName,
        statusColorHex,
      ];
}

/// The lead's most recent call — used to show a completed Call step read-only.
class LatestCall extends Equatable {
  const LatestCall({
    required this.callStatus,
    required this.notes,
    this.callTime = '',
    this.id = '',
  });

  final String callStatus; // INTERESTED / NOT_INTERESTED / CALL_BACK_REQUESTED
  final String notes;
  final String callTime; // raw call time, e.g. "16:30:00"
  final String id; // call record id — used as callId for stage completion

  bool get isInterested => callStatus.toUpperCase() == 'INTERESTED';
  bool get isNotInterested => callStatus.toUpperCase() == 'NOT_INTERESTED';
  bool get isCallback => callStatus.toUpperCase() == 'CALL_BACK_REQUESTED';
  bool get hasData => callStatus.isNotEmpty;

  factory LatestCall.fromJson(Map<String, dynamic> json) => LatestCall(
        callStatus: _s(json['callStatus']),
        notes: _s(json['notes']),
        callTime: _s(json['callTime']),
        id: _s(json['id']),
      );

  static const empty = LatestCall(callStatus: '', notes: '');

  @override
  List<Object?> get props => [callStatus, notes, callTime, id];
}

/// The lead's most recent visit — used to show a completed Visit step read-only.
class LatestVisit extends Equatable {
  const LatestVisit({
    required this.visitStatus,
    required this.visitDate,
    required this.visitTime,
    required this.dealerId,
    this.dealerName = '',
    this.id = '',
  });

  final String visitStatus; // VISIT_SCHEDULED / VISIT_COMPLETED
  final String visitDate; // raw, e.g. "2026-06-12" (backend currently sends a time here)
  final String visitTime; // raw, e.g. "20:01:00"
  final String dealerId; // selected dealer id, e.g. "15"
  final String dealerName; // optional — used to label the dealer on resume
  final String id; // visit record id — used as visitId for stage completion

  bool get hasData => visitStatus.isNotEmpty;

  factory LatestVisit.fromJson(Map<String, dynamic> json) => LatestVisit(
        visitStatus: _s(json['visitStatus']),
        visitDate: _s(json['visitDate']),
        visitTime: _s(json['visitTime']),
        dealerId: _s(json['dealerId']),
        dealerName: _s(json['dealerName']),
        id: _s(json['id']),
      );

  static const empty = LatestVisit(
    visitStatus: '',
    visitDate: '',
    visitTime: '',
    dealerId: '',
  );

  @override
  List<Object?> get props =>
      [visitStatus, visitDate, visitTime, dealerId, dealerName, id];
}

/// A still-open follow-up returned by getPreview (`pendingFollowup`). For a
/// scheduled callback this carries the saved callback date/time/comment so the
/// Call step can re-open with those values selected by default.
class PendingFollowup extends Equatable {
  const PendingFollowup({
    required this.id,
    required this.followupType,
    required this.followupStatus,
    required this.dueDate,
    required this.remarks,
    required this.time,
  });

  final String id;
  final String followupType; // CALL / VISIT
  final String followupStatus; // PENDING / ...
  final DateTime? dueDate; // callback date (date-only)
  final String remarks; // RM comment
  final String time; // raw callback time, e.g. "04:19 AM" (may be empty)

  bool get hasData => id.isNotEmpty;
  bool get isCall => followupType.toUpperCase() == 'CALL';
  bool get isVisit => followupType.toUpperCase() == 'VISIT';
  bool get isPending => followupStatus.toUpperCase() == 'PENDING';

  /// dueDate as a calendar date in local time, with no timezone shift (the API
  /// sends UTC midnight, so we rebuild from the date parts).
  DateTime? get date {
    final d = dueDate;
    if (d == null) return null;
    return DateTime(d.year, d.month, d.day);
  }

  factory PendingFollowup.fromJson(Map<String, dynamic> json) =>
      PendingFollowup(
        id: _s(json['id']),
        followupType: _s(json['followupType']),
        followupStatus: _s(json['followupStatus']),
        dueDate: _parseDueDate(_s(json['dueDate'])),
        remarks: _s(json['remarks']),
        time: _s(json['time']),
      );

  /// Parse the date part only — tolerates both "2026-06-12T00:00:00.000Z" and
  /// "2026-06-12 00:00:00+00" (whose "+00" offset Dart can't parse directly).
  static DateTime? _parseDueDate(String raw) {
    if (raw.isEmpty) return null;
    if (raw.length >= 10) return DateTime.tryParse(raw.substring(0, 10));
    return DateTime.tryParse(raw);
  }

  static const empty = PendingFollowup(
    id: '',
    followupType: '',
    followupStatus: '',
    dueDate: null,
    remarks: '',
    time: '',
  );

  @override
  List<Object?> get props =>
      [id, followupType, followupStatus, dueDate, remarks, time];
}

/// Parsed `POST /rm/getPreview` response: resume state for a lead.
class LeadPreview extends Equatable {
  const LeadPreview({
    required this.allowedActions,
    required this.leadDetails,
    required this.leadStages,
    required this.applicationStages,
    this.latestCall = LatestCall.empty,
    this.latestVisit = LatestVisit.empty,
    this.pendingFollowup = PendingFollowup.empty,
  });

  final AllowedActions allowedActions;
  final PreviewLeadDetails leadDetails;
  final List<StageItem> leadStages; // Call / Visit / Start Application
  final List<StageItem> applicationStages; // Upload Doc / Form / Consent / KYC / Submitted
  final LatestCall latestCall;
  final LatestVisit latestVisit;
  final PendingFollowup pendingFollowup;

  /// 0-based index of the `current` lead stage — where the RM resumes. Falls
  /// back to the first not-completed stage, else the last one.
  int get currentLeadStageIndex => _currentIndex(leadStages);
  int get currentApplicationStageIndex => _currentIndex(applicationStages);

  /// True once the "Start Application" lead stage is completed — the lead has
  /// moved past the Call/Visit interaction into the application phase, so the RM
  /// should land on the Application Process screen instead of the interaction
  /// stepper.
  bool get isApplicationStarted => leadStages.any((s) =>
      s.stageName.trim().toLowerCase() == 'start application' && s.completed);

  static int _currentIndex(List<StageItem> stages) {
    final ci = stages.indexWhere((s) => s.current);
    if (ci >= 0) return ci;
    final fi = stages.indexWhere((s) => !s.completed);
    if (fi >= 0) return fi;
    return stages.isEmpty ? 0 : stages.length - 1;
  }

  factory LeadPreview.fromJson(Map<String, dynamic> json) {
    final data = json['data'] is Map
        ? Map<String, dynamic>.from(json['data'] as Map)
        : json;

    final stagesJson = data['stages'] is Map
        ? Map<String, dynamic>.from(data['stages'] as Map)
        : <String, dynamic>{};

    List<StageItem> parseStages(dynamic v) {
      final list = (v is List ? v : const [])
          .whereType<Map>()
          .map((e) => StageItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      list.sort((a, b) => a.order.compareTo(b.order));
      return list;
    }

    return LeadPreview(
      allowedActions: data['allowedActions'] is Map
          ? AllowedActions.fromJson(
              Map<String, dynamic>.from(data['allowedActions'] as Map))
          : AllowedActions.empty,
      leadDetails: data['leadDetails'] is Map
          ? PreviewLeadDetails.fromJson(
              Map<String, dynamic>.from(data['leadDetails'] as Map))
          : PreviewLeadDetails.empty,
      leadStages: parseStages(stagesJson['leadStages']),
      applicationStages: parseStages(stagesJson['applicationStages']),
      latestCall: data['latestCall'] is Map
          ? LatestCall.fromJson(
              Map<String, dynamic>.from(data['latestCall'] as Map))
          : LatestCall.empty,
      latestVisit: data['latestVisit'] is Map
          ? LatestVisit.fromJson(
              Map<String, dynamic>.from(data['latestVisit'] as Map))
          : LatestVisit.empty,
      pendingFollowup: data['pendingFollowup'] is Map
          ? PendingFollowup.fromJson(
              Map<String, dynamic>.from(data['pendingFollowup'] as Map))
          : PendingFollowup.empty,
    );
  }

  static const empty = LeadPreview(
    allowedActions: AllowedActions.empty,
    leadDetails: PreviewLeadDetails.empty,
    leadStages: [],
    applicationStages: [],
  );

  @override
  List<Object?> get props => [
        allowedActions,
        leadDetails,
        leadStages,
        applicationStages,
        latestCall,
        latestVisit,
        pendingFollowup,
      ];
}
