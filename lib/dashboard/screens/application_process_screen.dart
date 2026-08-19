import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../bloc/lead_preview/lead_preview_bloc.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/local/application_stage_store.dart';
import '../../data/models/lead_item.dart';
import '../../data/models/lead_preview.dart';
import '../../data/repositories/lead_repository.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_colors.dart';
import '../application/application_details_screen.dart';
import '../application/consent_captured_screen.dart';
import '../application/esign_pending_screen.dart';
import '../application/field_investigation_screen.dart';
import '../application/financial_approval_screen.dart';
import '../application/kyc_verification_screen.dart';
import '../application/pre_disbursal_requirements_screen.dart';
import '../application/submit_application_screen.dart';
import '../widgets/interaction_ui.dart';
import 'upload_documents_screen.dart';

/// Application Process — the stages the RM completes after Start Application.
/// Everything here is driven by `POST /rm/getPreview`: the header from
/// `leadDetails` and the stepper from `applicationStages` (stage names + the
/// completed / current / locked flags). No static data.
class ApplicationProcessScreen extends StatelessWidget {
  const ApplicationProcessScreen(
      {super.key, required this.lead, this.autoResume = true});
  final LeadItem lead;
  // When false, the stepper does NOT auto-jump to the `current` stage on open —
  // used the first time Start Application is pressed so the RM lands on this
  // overview page instead of being pushed straight into Upload Document.
  final bool autoResume;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LeadPreviewBloc(repository: LeadRepository())
        ..add(LeadPreviewRequested(lead.id)),
      child: BlocBuilder<LeadPreviewBloc, LeadPreviewState>(
        builder: (context, state) {
          if (state.isFailure) {
            return _ProcessScaffold(
              child: _ProcessError(
                message: state.errorMessage ?? 'Failed to load application',
                onRetry: () => context
                    .read<LeadPreviewBloc>()
                    .add(LeadPreviewRequested(lead.id)),
              ),
            );
          }
          if (!state.isSuccess) {
            return const _ProcessScaffold(
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return ApplicationProcessView(
              lead: lead, preview: state.preview, autoResume: autoResume);
        },
      ),
    );
  }
}

/// Bare scaffold (AppBar + body) used for the loading / error states.
class _ProcessScaffold extends StatelessWidget {
  const _ProcessScaffold({required this.child});
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
        title: Text('Application Process',
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700, color: p.title)),
      ),
      body: child,
    );
  }
}

class _ProcessError extends StatelessWidget {
  const _ProcessError({required this.message, required this.onRetry});
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
            Icon(Icons.error_outline, size: 40, color: p.subtitle),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: p.subtitle)),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

/// The Application Process content for an already-loaded [LeadPreview]. Used
/// both by [ApplicationProcessScreen] (which self-fetches) and directly by
/// `LeadInteractionScreen` when the application is already started (so it can
/// reuse the preview it already loaded — no second getPreview call).
///
/// On open it RESUMES to the `current` application stage (getPreview's
/// `applicationStages` where `current:true`) — i.e. the page the RM last exited
/// on — pushing that stage's screen once (back returns to this stepper). The
/// stepper itself stays driven by getPreview (completed / current / locked).
class ApplicationProcessView extends StatefulWidget {
  const ApplicationProcessView(
      {super.key,
      required this.lead,
      required this.preview,
      this.autoResume = true});
  final LeadItem lead;
  final LeadPreview preview;
  // false → skip the one-time auto-resume to the `current` stage (first-time
  // Start Application lands on the stepper instead). See [_resumeToCurrent].
  final bool autoResume;

  @override
  State<ApplicationProcessView> createState() => _ApplicationProcessViewState();
}

class _ApplicationProcessViewState extends State<ApplicationProcessView> {
  // Resume only once per screen load (so backing out of the current-stage page
  // returns to the stepper instead of bouncing straight back in).
  bool _resumed = false;

  @override
  void initState() {
    super.initState();
    // Save the getPreview application stages so later screens can read the real
    // stageId + stageType from SharedPreferences (no page-to-page passing).
    ApplicationStageStore.instance
        .save(widget.lead.id, widget.preview.applicationStages);
    WidgetsBinding.instance.addPostFrameCallback((_) => _resumeToCurrent());
  }

  // Jump to the `current` stage's page (where the RM exited) — once.
  Future<void> _resumeToCurrent() async {
    // First-time Start Application: stay on the stepper, don't auto-jump.
    if (!widget.autoResume) return;
    if (_resumed || !mounted) return;
    final cur = _currentStage;
    if (cur == null) return;
    _resumed = true; // set before the await so we never double-resume
    final dest = await _resolveScreen(cur);
    if (dest == null || !mounted) return; // no screen → stay on the stepper
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => dest));
  }

  // The application stage flagged `current:true` (resume point).
  StageItem? get _currentStage {
    for (final s in widget.preview.applicationStages) {
      if (s.current) return s;
    }
    return null;
  }

  /// Tap a non-locked step → open its page. Only the steps with a built screen
  /// navigate; the rest show a "coming soon" placeholder.
  Future<void> _openStage(StageItem stage) async {
    final dest = await _resolveScreen(stage);
    if (!mounted) return;
    if (dest == null) {
      AppToast.show(context, '${stage.stageName} will be available soon.');
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => dest));
  }

  // Resolve a stage → its screen. The mapping is fully driven by the stage name
  // (see [_screenForStage]); the Customer Consent stage always lands on the
  // OTP-Verified (ConsentCaptured) screen — the Send-OTP / passcode pages are a
  // sub-flow and have no stepper step of their own.
  Future<Widget?> _resolveScreen(StageItem stage) async {
    return _screenForStage(stage);
  }

  // Map a stage → its screen, passing exactly the data that screen needs.
  Widget? _screenForStage(StageItem stage) {
    final name = stage.stageName.trim().toLowerCase();
    if (name == 'upload document' || name == 'upload documents') {
      return UploadDocumentsScreen(
        lead: widget.lead,
        stageId: stage.id,
        stageType: stage.stageType,
      );
    }
    // Application Form → the details/review screen (carries this stage's id+type).
    if (name == 'application form') {
      return ApplicationDetailsScreen(
        lead: widget.lead,
        stageId: stage.id,
        stageType: stage.stageType,
      );
    }
    // Customer Consent → the OTP-Verified (Consent Captured) screen. The Send-OTP
    // / passcode pages are a sub-flow (not stepper steps), so tapping or resuming
    // this stage always lands here. It self-fetches applicationId + applicant/co
    // details from /application/details, so nothing needs to be passed here.
    if (name == 'customer consent') {
      return ConsentCapturedScreen(lead: widget.lead);
    }
    if (name == 'kyc verification') {
      return KycVerificationScreen(lead: widget.lead);
    }
    // Application Submitted → the final submit screen (self-fetches details).
    if (name.contains('application submitted') || name.contains('submit')) {
      return SubmitApplicationScreen(lead: widget.lead);
    }
    // Financial / Loan Approval stage → the approval-status screen.
    if (name.contains('financial approval') ||
        name.contains('loan approval')) {
      return FinancialApprovalScreen(lead: widget.lead);
    }
    // Field Investigation stage → the FI screen.
    if (name.contains('field investigation')) {
      return FieldInvestigationScreen(lead: widget.lead);
    }
    // eSign Status stage → the eSign Pending/Success screen.
    if (name == 'esign status' || name.contains('esign')) {
      return ESignPendingScreen(lead: widget.lead);
    }
    // Predisbursal Uploads stage → the pre-disbursal requirements screen.
    if (name.contains('predisbursal') || name.contains('pre-disbursal')) {
      return PreDisbursalRequirementsScreen(lead: widget.lead);
    }
    return null; // no screen for this stage yet → stay on the stepper
  }

  // The Upload Document application stage (for the Start Application button).
  StageItem? get _uploadStage {
    for (final s in widget.preview.applicationStages) {
      final n = s.stageName.trim().toLowerCase();
      if (n == 'upload document' || n == 'upload documents') return s;
    }
    return widget.preview.applicationStages.isEmpty
        ? null
        : widget.preview.applicationStages.first;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final stages = widget.preview.applicationStages;
    // Once interaction is locked in (canInteraction), the RM can't return to the
    // Call/Visit flow — disable the HW back button + hide the top back arrow.
    // The only way out is Exit, which jumps straight to the dashboard.
    final lockExit = widget.preview.allowedActions.canInteraction;
    return PopScope(
      canPop: !lockExit,
      child: Scaffold(
        backgroundColor: p.surface,
        appBar: AppBar(
          backgroundColor: p.cardBg,
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: !lockExit,
          leading: lockExit
              ? null
              : IconButton(
                  icon:
                      Icon(Icons.arrow_back_ios_new, size: 20, color: p.title),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
          title: Text('Application Process',
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w700, color: p.title)),
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                children: [
                  LeadHeaderCard.details(details: widget.preview.leadDetails),
                  const SizedBox(height: 18),
                  if (stages.isEmpty)
                    InteractionCard(
                      child: Text('No application stages found.',
                          style: TextStyle(fontSize: 14, color: p.subtitle)),
                    )
                  else
                    InteractionCard(
                      child: Column(
                        children: [
                          for (var i = 0; i < stages.length; i++)
                            _ProcessStep(
                              index: i + 1,
                              title: stages[i].stageName,
                              subtitle: stages[i].desc,
                              completed: stages[i].completed,
                              current: stages[i].current,
                              locked: stages[i].locked,
                              isLast: i == stages.length - 1,
                              onTap: () => _openStage(stages[i]),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            InteractionBottomBar(
              actionLabel: 'Start Application',
              onExit: lockExit
                  ? () => Navigator.of(context)
                      .pushNamedAndRemoveUntil(AppRoutes.home, (r) => false)
                  : null,
              onAction: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => UploadDocumentsScreen(
                  lead: widget.lead,
                  stageId: _uploadStage?.id ?? '',
                  stageType: _uploadStage?.stageType ?? '',
                ),
              )),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProcessStep extends StatelessWidget {
  const _ProcessStep({
    required this.index,
    required this.title,
    required this.subtitle,
    required this.completed,
    required this.current,
    required this.locked,
    required this.isLast,
    this.onTap,
  });
  final int index;
  final String title;
  final String subtitle; // stage `desc` — hidden when empty
  final bool completed; // green tick (done)
  final bool current; // active step (resume here)
  final bool locked; // not reachable yet → dimmed
  final bool isLast;
  final VoidCallback? onTap; // tap a non-locked step to open its page

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // Circle: completed → green check; current → filled purple; locked/future →
    // outlined grey.
    final Widget circle = completed
        ? Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
                shape: BoxShape.circle, color: AppColors.success),
            child: const Icon(Icons.check, size: 17, color: Colors.white),
          )
        : Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: current ? AppColors.purple : p.cardBg,
              border: Border.all(
                  color: current ? AppColors.purple : p.fieldBorder,
                  width: 1.5),
            ),
            child: Text('$index',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: current ? Colors.white : p.subtitle)),
          );
    final titleColor = locked ? p.subtitle : p.title;
    final tappable = !locked && onTap != null;
    return Opacity(
      opacity: locked ? 0.55 : 1,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: tappable ? onTap : null,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  circle,
                  if (!isLast)
                    Expanded(
                      child: Container(
                          width: 2,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          color: completed ? AppColors.success : p.fieldBorder),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : 22, top: 3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: titleColor)),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(subtitle,
                            style: TextStyle(
                                fontSize: 13, color: p.subtitle, height: 1.35)),
                      ],
                    ],
                  ),
                ),
              ),
              if (tappable)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Icon(Icons.chevron_right,
                      size: 20, color: p.subtitle),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
