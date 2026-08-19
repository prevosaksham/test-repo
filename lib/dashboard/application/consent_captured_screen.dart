import 'package:flutter/material.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/local/application_stage_store.dart';
import '../../data/models/lead_item.dart';
import '../../data/models/lead_preview.dart';
import '../../data/models/person_detail.dart';
import '../../data/repositories/application_repository.dart';
import '../../data/repositories/lead_repository.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_colors.dart';
import '../widgets/interaction_ui.dart';
import 'application_flow_ui.dart';
import 'kyc_verification_screen.dart';

/// Step 3 of 5 — OTP verified confirmation. Shown after the consent passcodes
/// are verified. Re-fetches `/application/details` to show the applicant +
/// co-applicant cards (name / mobile / status) below the banners. Exit returns
/// home; Proceed continues to the final Consent Captured screen.
class ConsentCapturedScreen extends StatefulWidget {
  const ConsentCapturedScreen({super.key, required this.lead});
  // Only the lead is passed (for leadId). Everything else — applicationId,
  // stage, applicant/co-applicant name + mobile — is fetched here from
  // /application/details. Nothing is passed page-to-page.
  final LeadItem lead;

  @override
  State<ConsentCapturedScreen> createState() => _ConsentCapturedScreenState();
}

class _ConsentCapturedScreenState extends State<ConsentCapturedScreen> {
  final ApplicationRepository _repo = ApplicationRepository();
  ApplicationDetails? _details;
  bool _loading = true; // /application/details fetch in progress
  bool _proceeding = false; // save-term call in progress

  @override
  void initState() {
    super.initState();
    _load();
  }

  // Fetch /application/details — feeds the applicant/co-applicant cards + the
  // save-term call. Errors leave the cards blank.
  Future<void> _load() async {
    try {
      final d = await _repo.getApplicationDetails(leadId: widget.lead.id);
      if (mounted) setState(() => _details = d);
    } catch (_) {/* leave blank */} finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _appMobile() => _details?.applicant?.phoneNumber ?? '';
  String _coMobile() => _details?.coApplicant?.phoneNumber ?? '';

  // Status pill source — `data.consents.<party>.status == "VERIFIED"`, per party
  // rather than the one application-level flag. Falls back to
  // `application.isConsentAccepted` when the response carries no `consents`.
  bool _appAccepted() =>
      _details?.consents?.applicant.isVerified ??
      _details?.isConsentAccepted ??
      false;

  bool _coAccepted() =>
      _details?.consents?.coApplicant.isVerified ??
      _details?.isConsentAccepted ??
      false;

  // Captured On — `data.consents.<party>.capturedOn`, per party. Falls back to
  // the application-level `captureOn` when consents carries no date.
  String _appCapturedOn() => _orAppCaptureOn(
        _details?.consents?.applicant.capturedOn,
      );

  String _coCapturedOn() => _orAppCaptureOn(
        _details?.consents?.coApplicant.capturedOn,
      );

  String _orAppCaptureOn(String? v) =>
      (v != null && v.trim().isNotEmpty) ? v : (_details?.captureOn ?? '');

  // Proceed gate — `application.isConsentAccepted` from /application/details.
  // Null details (still loading, or the fetch failed) keep it disabled.
  bool get _proceedAllowed => _details?.isConsentAccepted ?? false;

  // Resolve the Customer Consent stage id + type, in order:
  //  1) SharedPreferences (saved from getPreview when the flow started),
  //  2) a fresh getPreview call (and cache it) — covers when the flow didn't
  //     pass through the Application Process screen this session,
  //  3) /application/details stages as a last resort.
  Future<({String id, String type})> _resolveConsentStage() async {
    StageItem? saved = await ApplicationStageStore.instance
        .stageByName(widget.lead.id, 'Customer Consent');
    if (saved == null || saved.id.isEmpty) {
      try {
        final preview = await LeadRepository().getPreview(leadId: widget.lead.id);
        await ApplicationStageStore.instance
            .save(widget.lead.id, preview.applicationStages);
        for (final s in preview.applicationStages) {
          if (s.stageName.trim().toLowerCase() == 'customer consent') {
            saved = s;
            break;
          }
        }
      } catch (_) {/* fall through to /details */}
    }
    if (saved != null && saved.id.isNotEmpty) {
      return (id: saved.id, type: saved.stageType);
    }
    final f = _consentStage();
    return (id: f?.stageId ?? '', type: f?.stageType ?? '');
  }

  // The Customer Consent stage from /application/details. Exact name first, then
  // any "consent" stage, then the first not-completed, else the last.
  ApplicationStage? _consentStage() {
    final stages = _details?.stages ?? const <ApplicationStage>[];
    if (stages.isEmpty) return null;
    for (final s in stages) {
      if (s.stageName.trim().toLowerCase() == 'customer consent') return s;
    }
    for (final s in stages) {
      if (s.stageName.trim().toLowerCase().contains('consent')) return s;
    }
    for (final s in stages) {
      if (!s.isCompleted) return s;
    }
    return stages.last;
  }

  // Proceed → save-term (stageId/stageType from the Customer Consent stage),
  // then the KYC Verification screen on success.
  Future<void> _onProceed() async {
    if (_proceeding) return;
    setState(() => _proceeding = true);
    try {
      // applicationId from /application/details (not passed in).
      final rawAppId = _details?.applicationId ?? '';
      final appId = int.tryParse(rawAppId.trim()) ?? rawAppId;
      final leadId = int.tryParse(widget.lead.id.trim()) ?? widget.lead.id;
      // Customer Consent stage id + type (SharedPreferences → live getPreview →
      // /application/details). See [_resolveConsentStage].
      final stage = await _resolveConsentStage();
      debugPrint('save-term stage → id:${stage.id} type:${stage.type}');
      final res = await _repo.saveTerm(
        applicationId: appId,
        leadId: leadId,
        stageId: stage.id,
        stageType: stage.type,
      );
      if (!mounted) return;
      final ok = res is Map && (res['success'] == true || res['status'] == true);
      final msg = (res is Map &&
              res['message'] is String &&
              (res['message'] as String).trim().isNotEmpty)
          ? (res['message'] as String).trim()
          : null;
      if (!ok) {
        _snack(msg ?? 'Could not save. Please try again.');
        return;
      }
      if (msg != null) _snack(msg, ok: true);
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => KycVerificationScreen(lead: widget.lead),
      ));
    } on ApiException catch (e) {
      if (mounted) _snack(e.message);
    } catch (_) {
      if (mounted) _snack('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _proceeding = false);
    }
  }

  void _snack(String msg, {bool ok = false}) {
    AppToast.show(context, msg,
        type: ok ? ToastType.success : ToastType.error);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppFlowScaffold(
      lockBack: true, // post-OTP — no going back to an earlier step
      title: 'Application Consent',
      stepText: 'Step 3 of 5',
      bottomBar: InteractionBottomBar(
        actionLabel: _proceeding ? 'Saving…' : 'Proceed',
        enabled: !_proceeding && _proceedAllowed,
        // Proceed → save-term, then the KYC Verification screen.
        onAction: _onProceed,
        onExit: () => Navigator.of(context)
            .pushNamedAndRemoveUntil(AppRoutes.home, (r) => false),
      ),
      // Loader until /application/details arrives, then the content.
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          const SizedBox(height: 8),
          const Center(child: SuccessBadge(bigCheck: true)),
          const SizedBox(height: 16),
          Center(
            child: Text('Consent Captured Successfully',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: p.title)),
          ),
          const SizedBox(height: 18),
          _capturedBanner(
              context, 'Applicant consent has been Captured Successfully.'),
          const SizedBox(height: 12),
          _personCard(
            nameLabel: 'Applicant Name:',
            name: _details?.applicant?.fullName ?? '',
            mobile: _appMobile(),
            // Status + Captured On come from data.consents.applicant.
            accepted: _appAccepted(),
            capturedOn: _appCapturedOn(),
          ),
          _capturedBanner(
              context, 'Co-Applicant consent has been Captured Successfully.'),
          // Below the banners: applicant + co-applicant cards (from /details).
          const SizedBox(height: 14),
          _personCard(
            nameLabel: 'Co-Applicant Name:',
            name: _details?.coApplicant?.fullName ?? '',
            mobile: _coMobile(),
            accepted: _coAccepted(),
            capturedOn: _coCapturedOn(),
          ),
        ],
      ),
    );
  }

  // Applicant / Co-Applicant card — Name, Mobile, Status. (Captured On will be
  // added once the API returns it.)
  // yyyy-mm-dd (or an ISO datetime) → dd-mm-yyyy. Leaves other shapes as-is.
  String _fmtDate(String v) {
    final s = v.trim();
    if (s.isEmpty) return s;
    final datePart = s.split('T').first.split(' ').first;
    final p = datePart.split('-');
    if (p.length == 3 && p[0].length == 4) {
      return '${p[2]}-${p[1]}-${p[0]}';
    }
    return v;
  }

  Widget _personCard({
    required String nameLabel,
    required String name,
    required String mobile,
    required bool accepted,
    String capturedOn = '',
  }) {
    return FlowCard(
      child: Column(
        children: [
          DetailRow(label: nameLabel, value: name),
          DetailRow(
              label: 'Mobile Number:',
              value: mobile.isNotEmpty ? '+91 $mobile' : ''),
          DetailRow(label: 'Captured On:', value: _fmtDate(capturedOn)),
          DetailRow(
            label: 'Status:',
            // isConsentAccepted: true → Consent Captured (green),
            // false → Not Captured (red).
            valueWidget: accepted
                ? const StatusPill(text: 'Consent Captured')
                : const StatusPill(
                    text: 'Not Captured',
                    color: AppColors.statusRed,
                    icon: Icons.cancel),
          ),
        ],
      ),
    );
  }

  // Green confirmation banner with a leading check.
  Widget _capturedBanner(BuildContext context, String text) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: const BoxDecoration(
                shape: BoxShape.circle, color: AppColors.success),
            child: const Icon(Icons.check, size: 15, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, height: 1.4, color: p.title),
            ),
          ),
        ],
      ),
    );
  }
}
