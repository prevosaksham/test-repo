import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../bloc/lead_preview/lead_preview_bloc.dart';
import '../../core/constants/app_assets.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/models/dealer.dart';
import '../../data/models/followup_item.dart';
import '../../data/models/lead_item.dart';
import '../../data/models/lead_preview.dart';
import '../../data/repositories/lead_repository.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_colors.dart';
import 'application_process_screen.dart';

/// Customer Interaction — CALL flow (step 1 of Call → Visit → Start Application).
/// On open it loads `getPreview(leadId)` so the stepper resumes wherever the RM
/// last exited (the `current` lead stage) and each step is driven entirely by
/// `leadStages` (completed / current / locked). Outcome (Call Received /
/// Schedule Callback) drives the form.
class LeadInteractionScreen extends StatelessWidget {
  const LeadInteractionScreen({super.key, required this.lead, this.initialKind});
  final LeadItem lead;

  /// When opened from a follow-up card, the step to land on by default:
  /// CALL → Call step, VISIT → Visit step. Null = resume at the server's
  /// `current` stage.
  final FollowupKind? initialKind;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          LeadPreviewBloc(repository: LeadRepository())
            ..add(LeadPreviewRequested(lead.id)),
      child: BlocBuilder<LeadPreviewBloc, LeadPreviewState>(
        builder: (context, state) {
          if (state.isFailure) {
            return _PreviewScaffold(
              child: _PreviewError(
                message: state.errorMessage ?? 'Failed to load lead',
                onRetry: () => context.read<LeadPreviewBloc>().add(
                  LeadPreviewRequested(lead.id),
                ),
              ),
            );
          }
          if (!state.isSuccess) {
            return const _PreviewScaffold(
              child: Center(child: CircularProgressIndicator()),
            );
          }
          // Application already started (Start Application stage completed) →
          // skip the Call/Visit interaction and land directly on the
          // Application Process screen (where Upload Document is current).
          if (state.preview.isApplicationStarted) {
            return ApplicationProcessView(
              lead: lead,
              preview: state.preview,
            );
          }
          return _InteractionView(
            lead: lead,
            preview: state.preview,
            initialKind: initialKind,
          );
        },
      ),
    );
  }
}

class _InteractionView extends StatefulWidget {
  const _InteractionView({
    required this.lead,
    required this.preview,
    this.initialKind,
  });
  final LeadItem lead;
  final LeadPreview preview;
  final FollowupKind? initialKind;

  @override
  State<_InteractionView> createState() => _LeadInteractionScreenState();
}

enum _Outcome { received, callback }

enum _Intent { interested, notInterested }

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]} ${d.year}';

String _fmtTime(TimeOfDay t) {
  var h = t.hour % 12;
  if (h == 0) h = 12;
  final m = t.minute.toString().padLeft(2, '0');
  return '${h.toString().padLeft(2, '0')}:$m ${t.hour < 12 ? 'AM' : 'PM'}';
}

// API date/time helpers — callDate & followUpsDate are date-only (2026-06-11),
// callTime is 12-hour hh:mm with AM/PM (e.g. 02:00 PM) (2026-06-12).
String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _hhmm(int hour, int minute) {
  var h = hour % 12;
  if (h == 0) h = 12;
  final m = minute.toString().padLeft(2, '0');
  return '${h.toString().padLeft(2, '0')}:$m ${hour < 12 ? 'AM' : 'PM'}';
}

/// Parse a saved callback time back into a TimeOfDay. Tolerates 12-hour
/// "hh:mm AM/PM" (what we send), and 24-hour "HH:mm" / "HH:mm:ss" (what the API
/// returns, e.g. "16:30:00"). Returns null on empty/unrecognised input.
TimeOfDay? _parseTimeOfDay(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final ampm = RegExp(r'^(\d{1,2}):(\d{2})(?::\d{2})?\s*([AaPp][Mm])$').firstMatch(s);
  if (ampm != null) {
    var h = int.parse(ampm.group(1)!) % 12;
    if (ampm.group(3)!.toUpperCase() == 'PM') h += 12;
    return TimeOfDay(hour: h % 24, minute: int.parse(ampm.group(2)!));
  }
  final h24 = RegExp(r'^(\d{1,2}):(\d{2})(?::\d{2})?$').firstMatch(s);
  if (h24 != null) {
    return TimeOfDay(
      hour: int.parse(h24.group(1)!) % 24,
      minute: int.parse(h24.group(2)!),
    );
  }
  return null;
}

/// Parse a date-only string (the YYYY-MM-DD prefix) into a DateTime. Returns
/// null when the value isn't a date (e.g. a bare "HH:mm:ss" time, which the
/// backend currently sends in `latestVisit.visitDate`).
DateTime? _parseDateOnly(String raw) {
  final s = raw.trim();
  if (s.length < 10) return null;
  return DateTime.tryParse(s.substring(0, 10));
}


class _LeadInteractionScreenState extends State<_InteractionView> {
  int _step = 0; // 0 = Call, 1 = Visit, 2 = Start Application

  final LeadRepository _leadRepo = LeadRepository();
  // Separate in-flight flags so each button shows ONLY its own loader.
  bool _proceeding = false; // bottom Proceed / Start Application button
  bool _scheduling = false; // Call "Schedule Callback" button
  bool _schedulingVisit = false; // Visit "Schedule Visit" button

  @override
  void initState() {
    super.initState();
    // Land on the lead's `current` stage straight from getPreview — i.e. the
    // leadStages entry flagged `current:true` (via currentLeadStageIndex). Fully
    // data-driven, nothing hardcoded: after Call Received → Proceed the reloaded
    // preview moves `current` to Visit, so the screen advances on its own.
    _step = widget.preview.currentLeadStageIndex.clamp(0, 2);
    // Both steps are pre-filled straight from getPreview so the stepper shows
    // each step's saved data — `pendingFollowup` (the latest open action) takes
    // priority over latestCall/latestVisit, routed by its followupType.
    final lc = widget.preview.latestCall;
    final lv = widget.preview.latestVisit;
    final pf = widget.preview.pendingFollowup;

    // ---- Call step ----
    //  • pending CALL follow-up → "Schedule Callback" (date / time / comment),
    //  • else latestCall → "Call Received" (intent + notes).
    if (pf.isCall && pf.isPending) {
      _outcome = _Outcome.callback;
      _callbackDate = pf.date;
      _callbackTime = _parseTimeOfDay(pf.time);
      final note = pf.remarks.isNotEmpty ? pf.remarks : lc.notes;
      if (note.isNotEmpty) _comments.text = note;
    } else if (lc.hasData) {
      _outcome = _Outcome.received;
      if (lc.isInterested) {
        _intent = _Intent.interested;
      } else if (lc.isNotInterested) {
        _intent = _Intent.notInterested;
      }
      if (lc.notes.isNotEmpty) _comments.text = lc.notes;
      // On resume, show the server's saved call time (latestCall.callTime)
      // instead of "now". The backend sends only the time (no callDate), so the
      // date part falls back to today; the TIME is the real server value.
      final ct = _parseTimeOfDay(lc.callTime);
      if (ct != null) {
        final now = DateTime.now();
        _intentAt = DateTime(now.year, now.month, now.day, ct.hour, ct.minute);
      }
    }

    // ---- Visit step ----
    //  • pending VISIT follow-up → that scheduled visit (date from dueDate + time),
    //  • else latestVisit → the submitted visit (visitTime; visitDate is a real
    //    date only when the backend sends one).
    // The values PREFILL the form, but it stays EDITABLE while the Visit stage
    // isn't completed (completed:false → editable). Only a COMPLETED Visit locks
    // to the read-only "Scheduled" row.
    if (pf.isVisit && pf.isPending) {
      _visitDate = pf.date;
      _visitTime = _parseTimeOfDay(pf.time);
    } else if (lv.hasData) {
      _visitDate = _parseDateOnly(lv.visitDate);
      _visitTime = _parseTimeOfDay(lv.visitTime);
    }
    // The dealer always comes from latestVisit — the pending VISIT follow-up
    // doesn't carry a dealerId, so set it regardless of the branch above.
    if (lv.dealerId.isNotEmpty) _dealer = lv.dealerId;
    final hasVisitData = (pf.isVisit && pf.isPending) || lv.hasData;
    _visitScheduled = hasVisitData && _isCompletedStage(1);
    // Load the Visit-step dealer list for this lead's OEM + city.
    _loadDealers();
  }

  Future<void> _loadDealers() async {
    final details = widget.preview.leadDetails;
    List<Dealer> dealers = const [];
    if (details.oemId.isNotEmpty) {
      setState(() {
        _dealersLoading = true;
        _dealersError = null;
      });
      try {
        dealers = await _leadRepo.getDealers(
          oemId: details.oemId,
          city: details.city,
        );
      } on ApiException catch (e) {
        if (mounted) setState(() => _dealersError = e.message);
      } catch (_) {
        if (mounted) setState(() => _dealersError = 'Could not load dealers');
      }
    }
    if (!mounted) return;
    setState(() {
      _dealerList = _withSelectedDealer(dealers);
      _dealersLoading = false;
    });
  }

  /// Keep the previously-selected dealer (from `latestVisit.dealerId`) visible
  /// in the dropdown on resume, even when the OEM/city-filtered list doesn't
  /// include it (or there was no OEM to query). Uses the dealer's real name
  /// when it's in the list / sent by the API, else a `Dealer #id` fallback.
  List<Dealer> _withSelectedDealer(List<Dealer> dealers) {
    final sel = _dealer;
    if (sel == null || sel.isEmpty || dealers.any((d) => d.id == sel)) {
      return dealers;
    }
    final name = widget.preview.latestVisit.dealerName.trim();
    return [
      Dealer(
        id: sel,
        name: name.isNotEmpty ? name : 'Dealer $sel',
        city: '',
        state: '',
      ),
      ...dealers,
    ];
  }

  /// Viewing a completed step → its data is shown read-only (not editable).
  bool get _readonly => _isCompletedStage(_step);

  /// Tap a stepper dot → jump to that step (only unlocked steps are tappable).
  void _goToStep(int i) {
    if (_isLocked(i) || i == _step) return;
    setState(() => _step = i);
  }

  // Step gating from `leadStages` (completed / current / locked), NOT
  // allowedActions. The step's primary button is DISABLED when that stage is:
  //   • locked=true    → not reachable yet (e.g. Start Application before Visit
  //                       is done; the API re-sends it locked=false once Visit
  //                       completes), or
  //   • completed=true → already done (Call/Visit can't be re-submitted; Start
  //                       Application becomes completed only after the form is
  //                       submitted, so it stays enabled until then).
  bool _isLocked(int i) {
    final stages = widget.preview.leadStages;
    return i >= 0 && i < stages.length && stages[i].locked;
  }

  bool _isCompletedStage(int i) {
    final stages = widget.preview.leadStages;
    return i >= 0 && i < stages.length && stages[i].completed;
  }

  /// The current step's primary (Proceed / Start Application) button is usable
  /// only when the stage isn't locked and isn't already completed.
  ///
  /// Start Application (step 2) is special: once the RM has completed the Visit
  /// and landed here, the button MUST be enabled. The cached preview can still
  /// mark this stage `locked:true` because it was loaded before the visit was
  /// done (we advance locally without re-fetching), so we ignore `locked` here
  /// and only disable once it's server-confirmed `completed` (form submitted).
  bool get _stepActionable {
    if (_step == 2) return !_isCompletedStage(2);
    // Visit (step 1): once the visit is scheduled/completed, Proceed must stay
    // enabled so the RM can advance to Start Application — even after the
    // reloaded preview marks this stage `completed`.
    if (_step == 1 && _visitScheduled) return true;
    return !_isLocked(_step) && !_isCompletedStage(_step);
  }

  // Step 1 — Call
  _Outcome? _outcome;
  _Intent? _intent;
  DateTime? _intentAt; // when the intent was marked (for the Call Date & Time)
  DateTime? _callbackDate;
  TimeOfDay? _callbackTime;
  final _comments = TextEditingController();

  // Step 2 — Visit
  String? _dealer; // selected dealer id
  DateTime? _visitDate;
  TimeOfDay? _visitTime;
  bool _visitScheduled = false;

  // Dealers fetched from getDealers (lead's OEM + city).
  List<Dealer> _dealerList = const [];
  bool _dealersLoading = false;
  String? _dealersError;

  /// "12 Jun 2026 08:01 PM" for the scheduled-visit row; tolerates a missing
  /// date (backend currently doesn't return a real visit date) → '—'.
  String get _visitScheduledLabel {
    final parts = [
      if (_visitDate != null) _fmtDate(_visitDate!),
      if (_visitTime != null) _fmtTime(_visitTime!),
    ];
    return parts.isEmpty ? '—' : parts.join(' ');
  }

  /// Display label of the selected dealer (looked up by id), or '—'.
  String get _selectedDealerLabel {
    if (_dealer == null) return '—';
    for (final d in _dealerList) {
      if (d.id == _dealer) return d.label;
    }
    return '—';
  }

  @override
  void dispose() {
    _comments.dispose();
    super.dispose();
  }

  bool get _canProceed {
    if (_step == 0) {
      // Schedule Callback has its own "Schedule" button, so Proceed stays
      // disabled there — only Call Received (with an intent) enables Proceed.
      if (_outcome == _Outcome.received) return _intent != null;
      return false;
    }
    if (_step == 1) return _visitScheduled; // Visit must be scheduled first
    return true; // step 2 — "Start Application" always enabled
  }

  bool get _canSchedule => _callbackDate != null && _callbackTime != null;
  bool get _canScheduleVisit =>
      _dealer != null && _visitDate != null && _visitTime != null;

  void _pickOutcome(_Outcome o) => setState(() {
    _outcome = o;
    // switching outcome clears the dependent selections
    _intent = null;
    _intentAt = null;
  });

  void _pickIntent(_Intent i) => setState(() {
    _intent = i;
    _intentAt = DateTime.now();
  });

  Future<void> _pickCallbackDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _callbackDate ?? now,
      firstDate: now,
      lastDate: DateTime(now.year + 1),
    );
    if (d != null) setState(() => _callbackDate = d);
  }

  // When the chosen date is today, a time earlier than "now" is not allowed.
  bool _isPastTimeToday(DateTime? date, TimeOfDay t) {
    final now = DateTime.now();
    final d = date ?? now;
    final isToday = d.year == now.year && d.month == now.month && d.day == now.day;
    if (!isToday) return false;
    final picked = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    // Compare at minute granularity — the picker only shows minutes, so a
    // selection matching the current minute (only seconds behind "now") should
    // still be allowed.
    final nowMinute = DateTime(now.year, now.month, now.day, now.hour, now.minute);
    return picked.isBefore(nowMinute);
  }

  Future<void> _pickCallbackTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _callbackTime ?? TimeOfDay.now(),
      // Force the 12-hour clock so the picker shows an AM/PM selector even when
      // the device is set to 24-hour time.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
        child: child!,
      ),
    );
    if (t == null) return;
    if (_isPastTimeToday(_callbackDate, t)) {
      _toast('You cannot select a past time for today');
      return;
    }
    setState(() => _callbackTime = t);
  }

  Future<void> _pickVisitDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _visitDate ?? now,
      firstDate: now,
      lastDate: DateTime(now.year + 1),
    );
    if (d != null) setState(() => _visitDate = d);
  }

  Future<void> _pickVisitTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _visitTime ?? TimeOfDay.now(),
      // Force the 12-hour clock so the picker shows an AM/PM selector even when
      // the device is set to 24-hour time.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
        child: child!,
      ),
    );
    if (t == null) return;
    if (_isPastTimeToday(_visitDate, t)) {
      _toast('You cannot select a past time for today');
      return;
    }
    setState(() => _visitTime = t);
  }

  Future<void> _scheduleVisit() async {
    if (!_canScheduleVisit || _schedulingVisit) return;
    // A visit set for now or earlier today = it already happened (VISIT_COMPLETED)
    // → stay here so the RM can Proceed to Start Application. A visit set for a
    // later time today or a future date = an upcoming visit (VISIT_SCHEDULED)
    // → show the success screen and return Home.
    final visitAt = DateTime(
      _visitDate!.year,
      _visitDate!.month,
      _visitDate!.day,
      _visitTime!.hour,
      _visitTime!.minute,
    );
    final isUpcoming = visitAt.isAfter(DateTime.now());
    setState(() => _schedulingVisit = true);
    try {
      final msg = await _leadRepo.scheduleVisit(
        leadId: widget.lead.id,
        dealerId: _dealer!,
        visitDate: _isoDate(_visitDate!), // date-only, e.g. 2026-05-25
        visitTime: _hhmm(_visitTime!.hour, _visitTime!.minute), // 04:30 PM
        visitStatus: isUpcoming ? 'VISIT_SCHEDULED' : 'VISIT_COMPLETED',
      );
      if (!mounted) return;
      if (isUpcoming) {
        // Upcoming visit → success screen shows the server message.
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VisitScheduleSuccessScreen(
              date: _visitDate!,
              time: _visitTime!,
              message: msg,
            ),
          ),
        );
      } else {
        // Visit already happened (VISIT_COMPLETED). Hide the "Schedule Visit"
        // button + enable Proceed right away (locally), so the RM stays on this
        // Visit step and reaches Start Application ONLY via Proceed.
        //
        // Deliberately NOT firing LeadPreviewRequested here: that reload emits a
        // `loading` state which swaps this whole view for the spinner, disposing
        // our State; on return initState re-runs and jumps `_step` to the
        // server's new `current` stage (Start Application) — i.e. it would skip
        // straight to Start Application instead of waiting for Proceed. The
        // local `_visitScheduled` flag already drives the correct UI (button
        // hidden + Proceed enabled), and the Start Application step re-fetches a
        // fresh preview itself when it needs the real call/visit ids.
        setState(() => _visitScheduled = true);
        if (msg.isNotEmpty) _toast(msg, ok: true);
      }
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _schedulingVisit = false);
    }
  }

  /// POST /rm/scheduleCall. Returns true on success. RM comment (notes) optional.
  /// The loader flag is owned by the caller (_proceed / _schedule) so each
  /// button shows only its own spinner.
  /// Returns the server result ({message, callStatus}) on success, or null on
  /// failure. Shows the server message as a toast.
  Future<({String message, String callStatus})?> _submitCall({
    required String callStatus,
    required String callTime,
    required bool followUpsRequired,
    String? followUpsDate,
  }) async {
    try {
      final result = await _leadRepo.scheduleCall(
        leadId: widget.lead.id,
        callStatus: callStatus,
        callDate: _isoDate(DateTime.now()),
        callTime: callTime,
        notes: _comments.text,
        followUpsRequired: followUpsRequired,
        followUpsDate: followUpsDate,
      );
      return result;
    } on ApiException catch (e) {
      _toast(e.message);
      return null;
    } catch (_) {
      _toast('Something went wrong. Please try again.');
      return null;
    }
  }

  // Green for a success message, red for an error/validation message.
  void _toast(String msg, {bool ok = false}) {
    if (!mounted) return;
    AppToast.show(context, msg,
        type: ok ? ToastType.success : ToastType.error);
  }

  Future<void> _proceed() async {
    if (!_canProceed || _proceeding) return;
    if (_step == 0) {
      // Call Received → record the call outcome (INTERESTED / NOT_INTERESTED,
      // no follow-up) before moving to Visit.
      final now = DateTime.now();
      setState(() => _proceeding = true);
      try {
        final result = await _submitCall(
          callStatus: _intent == _Intent.interested
              ? 'INTERESTED'
              : 'NOT_INTERESTED',
          callTime: _hhmm(now.hour, now.minute), // call happened now
          followUpsRequired: false,
        );
        if (result != null && mounted) {
          if (result.message.isNotEmpty) {
            _toast(result.message, ok: true); // server success msg
          }
          if (result.callStatus == 'NOT_INTERESTED') {
            // Lead rejected — there is no Visit step. Return to a fresh
            // dashboard (rebuilding it re-fires the dashboard API = refresh).
            Navigator.of(context)
                .pushNamedAndRemoveUntil(AppRoutes.home, (r) => false);
          } else {
            // Call completed → reload getPreview so the stepper advances to the
            // Visit step; the reloaded screen resumes there.
            context.read<LeadPreviewBloc>().add(
              LeadPreviewRequested(widget.lead.id),
            );
          }
        }
      } finally {
        if (mounted) setState(() => _proceeding = false);
      }
    } else if (_step == 1) {
      setState(() => _step = 2); // Visit → Start Application
    } else {
      // Start Application → complete the lead stage (callId + visitId), then
      // open the application flow with the REFRESHED preview (now carrying the
      // unlocked application stages). The earlier Call/Visit flow is untouched.
      setState(() => _proceeding = true);
      try {
        // The in-session preview can predate the just-completed visit, leaving
        // latestCall.id / latestVisit.id empty (→ "visitId is required"). Pull a
        // fresh preview for the real ids when they're missing.
        var src = widget.preview;
        if (src.latestVisit.id.isEmpty || src.latestCall.id.isEmpty) {
          src = await _leadRepo.getPreview(leadId: widget.lead.id);
        }
        await _leadRepo.completeStartApplication(
          leadId: widget.lead.id,
          callId: src.latestCall.id,
          visitId: src.latestVisit.id,
        );
        // completeStartApplication unlocks the applicationStages server-side;
        // ApplicationProcessScreen re-fetches getPreview itself to render them.
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            // First-time Start Application → land on the Application Process
            // overview (don't auto-jump into the current/Upload Document stage).
            builder: (_) =>
                ApplicationProcessScreen(lead: widget.lead, autoResume: false),
          ),
        );
      } on ApiException catch (e) {
        _toast(e.message);
      } catch (_) {
        _toast('Something went wrong. Please try again.');
      } finally {
        if (mounted) setState(() => _proceeding = false);
      }
    }
  }

  Future<void> _schedule() async {
    if (!_canSchedule || _scheduling) return;
    // Schedule Callback → CALL_BACK_REQUESTED. followUpsDate is sent date-only
    // (e.g. 2026-06-11), as requested.
    setState(() => _scheduling = true);
    try {
      final result = await _submitCall(
        callStatus: 'CALL_BACK_REQUESTED',
        callTime: _hhmm(
          _callbackTime!.hour,
          _callbackTime!.minute,
        ), // callback time
        followUpsRequired: true,
        followUpsDate: _isoDate(_callbackDate!),
      );
      if (result != null && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CallRescheduleSuccessScreen(
              date: _callbackDate!,
              time: _callbackTime!,
              message: result.message,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _scheduling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.surface,
      appBar: AppBar(
        backgroundColor: p.cardBg,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, size: 20, color: p.title),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Lead Interaction',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: p.title,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              children: [
                _LeadHeader(
                  lead: widget.lead,
                  previewLocation: widget.preview.leadDetails.location,
                ),
                const SizedBox(height: 18),
                _Stepper(
                  active: _step,
                  stages: widget.preview.leadStages,
                  onStepTap: _goToStep,
                ),
                const SizedBox(height: 18),
                // A completed step is shown read-only (IgnorePointer blocks the
                // radios / intent buttons / comment field from being changed).
                IgnorePointer(
                  ignoring: _readonly,
                  child: Column(
                    children: [
                      if (_step == 0) ..._callStep(),
                      if (_step == 1) _visitCard(),
                      if (_step == 2) ..._startAppStep(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _bottomBar(),
        ],
      ),
    );
  }

  // ---- Call Details ----
  Widget _callDetailsCard() {
    final p = context.palette;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Call Details',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: p.title,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Select Call Outcome',
            style: TextStyle(fontSize: 13, color: p.subtitle),
          ),
          const SizedBox(height: 12),
          _OutcomeOption(
            selected: _outcome == _Outcome.received,
            title: 'Call Received',
            subtitle: 'Customer answered the call',
            icon: AppAssets.calling,
            iconColor: AppColors.chartApproved,
            onTap: () => _pickOutcome(_Outcome.received),
          ),
          const SizedBox(height: 10),
          _OutcomeOption(
            selected: _outcome == _Outcome.callback,
            title: 'Schedule Callback',
            subtitle: 'Customer requested callback',
            icon: AppAssets.schedule,
            iconColor: AppColors.chartProgress,
            onTap: () => _pickOutcome(_Outcome.callback),
          ),
        ],
      ),
    );
  }

  // ---- Customer Intent (only when Call Received) ----
  Widget _intentCard() {
    final p = context.palette;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Customer Intent',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: p.title,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Is customer interested?',
            style: TextStyle(fontSize: 13, color: p.subtitle),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _IntentButton(
                  label: 'Mark Interested',
                  selected: _intent == _Intent.interested,
                  selectedColor: AppColors.chartApproved,
                  onTap: () => _pickIntent(_Intent.interested),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _IntentButton(
                  label: 'Not Interested',
                  selected: _intent == _Intent.notInterested,
                  selectedColor: AppColors.statusRed,
                  onTap: () => _pickIntent(_Intent.notInterested),
                ),
              ),
            ],
          ),
          if (_intent != null) ...[
            const SizedBox(height: 12),
            _IntentResult(
              interested: _intent == _Intent.interested,
              at: _intentAt ?? DateTime.now(),
            ),
          ],
        ],
      ),
    );
  }

  // ---- Schedule Callback (date + time) ----
  Widget _callbackCard() {
    final p = context.palette;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Schedule Callback',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: p.title,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Pick a callback date & time',
            style: TextStyle(fontSize: 13, color: p.subtitle),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _PickerField(
                  icon: Icons.calendar_today_outlined,
                  label: 'Callback Date',
                  value: _callbackDate == null
                      ? 'Select date'
                      : _fmtDate(_callbackDate!),
                  filled: _callbackDate != null,
                  onTap: _pickCallbackDate,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PickerField(
                  icon: Icons.access_time,
                  label: 'Callback Time',
                  value: _callbackTime == null
                      ? 'Select time'
                      : _fmtTime(_callbackTime!),
                  filled: _callbackTime != null,
                  onTap: _pickCallbackTime,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---- Schedule button (shown below RM Comments for Schedule Callback) ----
  Widget _scheduleButton() {
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppColors.buttonGradient,
          borderRadius: BorderRadius.circular(12),
        ),
        child: ElevatedButton(
          onPressed: (_canSchedule && !_scheduling) ? _schedule : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: _scheduling
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'Schedule',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    );
  }

  // ---- RM Comments ----
  Widget _commentsField() {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'RM Comments ',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: p.title,
                ),
              ),
              TextSpan(
                text: '(Optional)',
                style: TextStyle(fontSize: 13, color: p.subtitle),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _comments,
          maxLines: 4,
          textInputAction: TextInputAction.done,
          style: TextStyle(fontSize: 14, color: p.title),
          decoration: InputDecoration(
            hintText: 'Add note about the call',
            hintStyle: TextStyle(fontSize: 14, color: p.subtitle),
            filled: true,
            fillColor: p.cardBg,
            contentPadding: const EdgeInsets.all(14),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: p.fieldBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.purple),
            ),
          ),
        ),
      ],
    );
  }

  // ---- Step 1 content (Call) ----
  List<Widget> _callStep() => [
    _callDetailsCard(),
    const SizedBox(height: 14),
    if (_outcome == _Outcome.received) _intentCard(),
    if (_outcome == _Outcome.callback) _callbackCard(),
    const SizedBox(height: 18),
    _commentsField(),
    // Schedule Callback only: the Schedule button sits below RM Comments.
    if (_outcome == _Outcome.callback) ...[
      const SizedBox(height: 18),
      _scheduleButton(),
    ],
  ];

  // ---- Step 2 content (Visit Schedule) ----
  Widget _visitCard() {
    final p = context.palette;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Visit Schedule',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: p.title,
            ),
          ),
          const SizedBox(height: 14),
          _FieldLabel('Dealer'),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.fieldBorder),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                menuMaxHeight: 320, // bounded height → long lists scroll
                // Only show the value once it's actually in the loaded list,
                // else DropdownButton asserts (the prefilled dealerId arrives
                // before getDealers finishes).
                value: _dealerList.any((d) => d.id == _dealer) ? _dealer : null,
                hint: Text(
                  _dealersLoading
                      ? 'Loading dealers…'
                      : _dealersError != null
                          ? _dealersError!
                          : _dealerList.isEmpty
                              ? 'No dealers found'
                              : 'Select dealer',
                  style: TextStyle(fontSize: 14, color: p.subtitle),
                ),
                icon: _dealersLoading
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.keyboard_arrow_down, color: p.subtitle),
                items: _dealerList
                    .map(
                      (d) => DropdownMenuItem(
                        value: d.id,
                        child: Text(
                          d.label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, color: p.title),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (_visitScheduled || _dealersLoading)
                    ? null
                    : (v) => setState(() => _dealer = v),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _FieldLabel('Visit Date'),
          const SizedBox(height: 6),
          _LabeledFieldBox(
            icon: Icons.calendar_today_outlined,
            value: _visitDate == null ? 'Select date' : _fmtDate(_visitDate!),
            filled: _visitDate != null,
            onTap: _visitScheduled ? null : _pickVisitDate,
          ),
          const SizedBox(height: 14),
          _FieldLabel('Visit Time'),
          const SizedBox(height: 6),
          _LabeledFieldBox(
            icon: Icons.access_time,
            value: _visitTime == null ? 'Select time' : _fmtTime(_visitTime!),
            filled: _visitTime != null,
            onTap: _visitScheduled ? null : _pickVisitTime,
          ),
          if (!_visitScheduled) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: (_canScheduleVisit && !_schedulingVisit)
                    ? _scheduleVisit
                    : null,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 11,
                  ),
                  side: BorderSide(
                    color: _canScheduleVisit
                        ? AppColors.statusRed
                        : p.fieldBorder,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _schedulingVisit
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.statusRed,
                        ),
                      )
                    : Text(
                        'Schedule Visit',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _canScheduleVisit
                              ? AppColors.statusRed
                              : p.subtitle,
                        ),
                      ),
              ),
            ),
          ],
          if (_visitScheduled) ...[
            const SizedBox(height: 14),
            _ScheduledRow(
              label: 'Scheduled',
              detailLabel: 'Visit Date & Time',
              detail: _visitScheduledLabel,
            ),
          ],
        ],
      ),
    );
  }

  // ---- Step 3 content (Start Application summary) ----
  List<Widget> _startAppStep() {
    final p = context.palette;
    final comments = _comments.text.trim();
    return [
      _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Call Details',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: p.title,
              ),
            ),
            const SizedBox(height: 12),
            _summaryRow('Call Outcome', 'Call Received'),
            _summaryRow(
              'Call Date & Time',
              '${_fmtDate(_intentAt ?? DateTime.now())} ${_fmtTime(TimeOfDay.fromDateTime(_intentAt ?? DateTime.now()))}',
            ),
            _summaryRow(
              'Interested Status',
              _intent == _Intent.notInterested
                  ? 'Not Interested'
                  : 'Interested',
              valueColor: _intent == _Intent.notInterested
                  ? AppColors.statusRed
                  : AppColors.chartApproved,
            ),
            _summaryRow('RM Comments', comments.isEmpty ? '—' : comments),
          ],
        ),
      ),
      const SizedBox(height: 14),
      _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Visit Details',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: p.title,
              ),
            ),
            const SizedBox(height: 12),
            _summaryRow('Dealer', _selectedDealerLabel),
            _summaryRow(
              'Visit Date',
              _visitDate == null ? '—' : _fmtDate(_visitDate!),
            ),
            _summaryRow(
              'Visit Time',
              _visitTime == null ? '—' : _fmtTime(_visitTime!),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.purple.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.purple.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Text(
              'Ready to start application',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: p.title,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Customer is interested and dealer visit is scheduled. You can start the application process now.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: p.subtitle, height: 1.4),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _summaryRow(String label, String value, {Color? valueColor}) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(fontSize: 13.5, color: p.subtitle),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: valueColor ?? p.title,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- Bottom bar: Exit / Proceed ----
  Widget _bottomBar() {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: p.cardBg,
        border: Border(top: BorderSide(color: p.fieldBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).maybePop(),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  side: BorderSide(color: p.fieldBorder),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Exit',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: p.title,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Opacity(
                opacity: (_canProceed && _stepActionable && !_proceeding)
                    ? 1
                    : 0.5,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: AppColors.buttonGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ElevatedButton(
                    onPressed: (_canProceed && _stepActionable && !_proceeding)
                        ? _proceed
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      disabledBackgroundColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _proceeding
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _step == 2 ? 'Start Application' : 'Proceed',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pieces
// ---------------------------------------------------------------------------

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.fieldBorder),
      ),
      child: child,
    );
  }
}

class _LeadHeader extends StatelessWidget {
  const _LeadHeader({required this.lead, this.previewLocation = ''});
  final LeadItem lead;

  /// City + state from getPreview's leadDetails — used when the LeadItem itself
  /// has no location (e.g. opened from a follow-up card, which lacks city/state).
  final String previewLocation;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final statusColor = _hex(lead.status.colorHex, AppColors.chartProgress);
    final loc = lead.location.isNotEmpty ? lead.location : previewLocation;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Lead ID',
                      style: TextStyle(fontSize: 12, color: p.subtitle),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      lead.leadNo.isEmpty ? '—' : lead.leadNo,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.purple,
                      ),
                    ),
                  ],
                ),
              ),
              if (lead.status.displayName.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    lead.status.displayName,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: p.fieldBorder),
          ),
          Text(
            lead.name.isEmpty ? '—' : lead.name,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: p.title,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.call, size: 16, color: p.subtitle),
              const SizedBox(width: 5),
              Text(
                lead.mobile.isEmpty ? '—' : lead.mobile,
                style: TextStyle(fontSize: 14, color: p.subtitle),
              ),
              if (loc.isNotEmpty) ...[
                const SizedBox(width: 14),
                Icon(Icons.location_on_outlined, size: 17, color: p.subtitle),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    loc,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: p.subtitle),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.active,
    this.stages = const [],
    this.onStepTap,
  });
  final int active; // 0-based (the local current step)
  final List<StageItem> stages; // from getPreview leadStages (completed/locked)
  final ValueChanged<int>? onStepTap; // tap a non-locked step to view it
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    const fallback = ['Call', 'Visit', 'Start Application'];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < 3; i++) ...[
          () {
            final st = i < stages.length ? stages[i] : null;
            // Done = server says completed OR the RM has locally moved past it.
            final completed = (st?.completed ?? false) || i < active;
            final current = i == active;
            // locked=true → step disabled (dimmed); enabled otherwise.
            final locked = (st?.locked ?? false) && !completed && !current;
            final label = (st?.stageName.isNotEmpty ?? false)
                ? st!.stageName
                : fallback[i];
            // Tappable only when the stage isn't locked (locked:false).
            final tappable = !(st?.locked ?? false);
            return Opacity(
              opacity: locked ? 0.45 : 1,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: tappable ? () => onStepTap?.call(i) : null,
                child: Column(
                  children: [
                    _StepCircle(
                      index: i + 1,
                      completed: completed,
                      current: current,
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: 78,
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: (completed || current)
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: (completed || current) ? p.title : p.subtitle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }(),
          if (i < 2)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 13),
                child: Container(height: 2, color: p.fieldBorder),
              ),
            ),
        ],
      ],
    );
  }
}

class _StepCircle extends StatelessWidget {
  const _StepCircle({
    required this.index,
    required this.completed,
    required this.current,
  });
  final int index;
  final bool completed; // step done → green check
  final bool current; // step in progress → purple number
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // Completed → solid green circle with a white check.
    if (completed) {
      return Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.success,
        ),
        child: const Icon(Icons.check, size: 16, color: Colors.white),
      );
    }
    // Current → filled purple; future → outlined. Both show the step number.
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: current ? AppColors.purple : p.cardBg,
        border: Border.all(
          color: current ? AppColors.purple : p.fieldBorder,
          width: 1.5,
        ),
      ),
      child: Text(
        '$index',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: current ? Colors.white : p.subtitle,
        ),
      ),
    );
  }
}

class _OutcomeOption extends StatelessWidget {
  const _OutcomeOption({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.onTap,
  });
  final bool selected;
  final String title;
  final String subtitle;
  final String icon;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: p.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.purple : p.fieldBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            _Radio(selected: selected),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: p.title,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12.5, color: p.subtitle),
                  ),
                ],
              ),
            ),
            AppIcon(icon, size: 22, color: iconColor),
          ],
        ),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  const _Radio({required this.selected});
  final bool selected;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? AppColors.purple : p.fieldBorder,
          width: selected ? 6 : 1.5,
        ),
      ),
    );
  }
}

class _IntentButton extends StatelessWidget {
  const _IntentButton({
    required this.label,
    required this.selected,
    required this.selectedColor,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final Color selectedColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? selectedColor.withValues(alpha: 0.10) : p.cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? selectedColor : p.fieldBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: selected ? selectedColor : p.subtitle,
          ),
        ),
      ),
    );
  }
}

class _IntentResult extends StatelessWidget {
  const _IntentResult({required this.interested, required this.at});
  final bool interested;
  final DateTime at;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = interested ? AppColors.chartApproved : AppColors.statusRed;
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.fieldBorder),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Column(
                  children: [
                    Icon(
                      interested ? Icons.check_circle : Icons.cancel_outlined,
                      size: 22,
                      color: color,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      interested ? 'Interested' : 'Not Interested',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: p.title,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            VerticalDivider(width: 1, color: p.fieldBorder),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Call Date & Time',
                      style: TextStyle(fontSize: 12, color: p.subtitle),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_fmtDate(at)} ${_fmtTime(TimeOfDay.fromDateTime(at))}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: p.title,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.icon,
    required this.label,
    required this.value,
    required this.filled,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String value;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.fieldBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: p.subtitle)),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(icon, size: 16, color: AppColors.purple),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    value,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: filled ? p.title : p.subtitle,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: p.title,
      ),
    );
  }
}

class _LabeledFieldBox extends StatelessWidget {
  const _LabeledFieldBox({
    required this.icon,
    required this.value,
    required this.filled,
    required this.onTap,
  });
  final IconData icon;
  final String value;
  final bool filled;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.fieldBorder),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: filled ? FontWeight.w600 : FontWeight.w400,
                  color: filled ? p.title : p.subtitle,
                ),
              ),
            ),
            Icon(icon, size: 18, color: p.subtitle),
          ],
        ),
      ),
    );
  }
}

class _ScheduledRow extends StatelessWidget {
  const _ScheduledRow({
    required this.label,
    required this.detailLabel,
    required this.detail,
  });
  final String label;
  final String detailLabel;
  final String detail;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.fieldBorder),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Column(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      size: 22,
                      color: AppColors.chartApproved,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: p.title,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            VerticalDivider(width: 1, color: p.fieldBorder),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      detailLabel,
                      style: TextStyle(fontSize: 12, color: p.subtitle),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      detail,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: p.title,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Call Rescheduled Successfully!" — shown after Schedule Callback → Proceed.
class CallRescheduleSuccessScreen extends StatelessWidget {
  const CallRescheduleSuccessScreen({
    super.key,
    required this.date,
    required this.time,
    required this.message,
  });
  final DateTime date;
  final TimeOfDay time;
  final String message; // server message, e.g. "Call created successfully"

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // This is a terminal screen: no back arrow and the hardware back button is
    // disabled — the only way forward is "Back to Home".
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: p.surface,
        appBar: AppBar(
          backgroundColor: p.surface,
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
          title: Text(
            'Lead Interaction',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: p.title,
            ),
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(16, 30, 16, 16),
          child: Column(
            children: [
              Container(
                width: 96,
                height: 96,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.chartApproved.withValues(alpha: 0.12),
                ),
                child: const CircleAvatar(
                  radius: 30,
                  backgroundColor: AppColors.success,
                  child: Icon(Icons.check, color: Colors.white, size: 30),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your callback has been rescheduled',
                style: TextStyle(fontSize: 14, color: p.subtitle),
              ),
              const SizedBox(height: 20),
              _Card(
                child: Column(
                  children: [
                    _infoRow(
                      context,
                      Icons.calendar_today_outlined,
                      'Callback Date',
                      _fmtDate(date),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Divider(height: 1, color: p.fieldBorder),
                    ),
                    _infoRow(
                      context,
                      Icons.access_time,
                      'Callback Time',
                      _fmtTime(time),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: AppColors.buttonGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ElevatedButton(
                    // Fresh DashboardShell at the Home tab (clears the stack), so
                    // Home re-fetches its API and there's nothing to go back to.
                    onPressed: () => Navigator.of(
                      context,
                    ).pushNamedAndRemoveUntil(AppRoutes.home, (r) => false),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Back to Home',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    final p = context.palette;
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: p.fieldBorder),
          ),
          child: Icon(icon, size: 18, color: AppColors.purple),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: p.subtitle)),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: p.title,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Shown after scheduling an upcoming (future) visit — terminal, like
/// [CallRescheduleSuccessScreen], leading only back to Home.
class VisitScheduleSuccessScreen extends StatelessWidget {
  const VisitScheduleSuccessScreen({
    super.key,
    required this.date,
    required this.time,
    required this.message,
  });
  final DateTime date;
  final TimeOfDay time;
  final String message; // server message, e.g. "Visit created successfully"

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: p.surface,
        appBar: AppBar(
          backgroundColor: p.surface,
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
          title: Text(
            'Lead Interaction',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: p.title,
            ),
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(16, 30, 16, 16),
          child: Column(
            children: [
              Container(
                width: 96,
                height: 96,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.chartApproved.withValues(alpha: 0.12),
                ),
                child: const CircleAvatar(
                  radius: 30,
                  backgroundColor: AppColors.success,
                  child: Icon(Icons.check, color: Colors.white, size: 30),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(height: 8),
              const SizedBox(height: 20),
              _Card(
                child: Column(
                  children: [
                    _infoRow(
                      context,
                      Icons.calendar_today_outlined,
                      'Visit Date',
                      _fmtDate(date),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Divider(height: 1, color: p.fieldBorder),
                    ),
                    _infoRow(
                      context,
                      Icons.access_time,
                      'Visit Time',
                      _fmtTime(time),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: AppColors.buttonGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(
                      context,
                    ).pushNamedAndRemoveUntil(AppRoutes.home, (r) => false),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Back to Home',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    final p = context.palette;
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: p.fieldBorder),
          ),
          child: Icon(icon, size: 18, color: AppColors.purple),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: p.subtitle)),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: p.title,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

Color _hex(String hex, Color fallback) {
  var h = hex.replaceAll('#', '').trim();
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  return v == null ? fallback : Color(v);
}

/// Plain scaffold (same AppBar as the loaded screen) for the getPreview
/// loading / error states.
class _PreviewScaffold extends StatelessWidget {
  const _PreviewScaffold({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.surface,
      appBar: AppBar(
        backgroundColor: p.cardBg,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, size: 20, color: p.title),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Lead Interaction',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: p.title,
          ),
        ),
      ),
      body: child,
    );
  }
}

class _PreviewError extends StatelessWidget {
  const _PreviewError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 44, color: p.subtitle),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: p.subtitle),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
