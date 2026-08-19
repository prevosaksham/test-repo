import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/constants/app_assets.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/models/lead_item.dart';
import '../../data/repositories/application_repository.dart';
import '../../theme/app_colors.dart';
import '../widgets/interaction_ui.dart';
import 'application_flow_ui.dart';
import 'consent_captured_screen.dart';

/// Step 3 of 5 — Link mode. Confirms the consent links were sent to the
/// applicant & co-applicant, with per-applicant resend (`/consent/resend-link`).
/// Proceed continues to KYC (disabled for now — consent not captured yet).
class ConsentLinkSentScreen extends StatefulWidget {
  const ConsentLinkSentScreen({
    super.key,
    required this.lead,
    this.applicationId = '',
    this.applicationNo = '',
    this.applicantMobile = '',
    this.coApplicantMobile = '',
    this.consentIds = const [],
  });
  final LeadItem lead;
  // Application id (lead.id — the form-details API id) + application number,
  // carried from Application Details.
  final String applicationId;
  final String applicationNo;
  final String applicantMobile; // real numbers passed from Application Details
  final String coApplicantMobile;
  final List<int> consentIds; // consent ids — needed for resend-link

  @override
  State<ConsentLinkSentScreen> createState() => _ConsentLinkSentScreenState();
}

class _ConsentLinkSentScreenState extends State<ConsentLinkSentScreen> {
  final ApplicationRepository _repo = ApplicationRepository();

  bool _sendingApplicant = false; // resend-link in progress (applicant)
  bool _sendingCo = false; // resend-link in progress (co-applicant)

  Timer? _statusTimer; // polls /consent/status every 5s
  bool _checking = false; // a status call is in flight
  bool _navigated = false; // already moved on (guard against double-nav)

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  // Poll consent acceptance every 5s; once accepted → Consent Captured screen.
  void _startPolling() {
    if (widget.applicationId.trim().isEmpty) return;
    _checkStatus(); // immediate first check, then every 5s
    _statusTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _checkStatus());
  }

  Future<void> _checkStatus() async {
    if (_checking || _navigated) return;
    _checking = true;
    try {
      final appId =
          int.tryParse(widget.applicationId.trim()) ?? widget.applicationId;
      debugPrint('[CONSENT-POLL] → /consent/status { applicationId: $appId }');
      final accepted = await _repo.getConsentAccepted(applicationId: appId);
      debugPrint('[CONSENT-POLL] ← isConsentAccepted = $accepted');
      if (!mounted || _navigated || !accepted) return;
      _navigated = true;
      _statusTimer?.cancel();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ConsentCapturedScreen(lead: widget.lead),
        ),
      );
    } finally {
      _checking = false;
    }
  }

  void _snack(String msg, {bool ok = false}) => AppToast.show(context, msg,
      type: ok ? ToastType.success : ToastType.error);

  // The server's message from a consent response (null when none).
  String? _serverMsg(dynamic res) =>
      (res is Map &&
              res['message'] is String &&
              (res['message'] as String).trim().isNotEmpty)
          ? (res['message'] as String).trim()
          : null;

  // Resend the consent LINK to a SINGLE applicant type
  // (`POST /consent/resend-link`).
  Future<void> _resend(String applicantType) async {
    final isApplicant = applicantType == 'APPLICANT';
    if (isApplicant ? _sendingApplicant : _sendingCo) return;
    // This person's mobile — the API requires a mobileNumber per applicantType.
    final mobile =
        (isApplicant ? widget.applicantMobile : widget.coApplicantMobile)
            .trim();
    if (mobile.isEmpty) {
      _snack('Mobile number not available for this ${isApplicant ? 'applicant' : 'co-applicant'}.');
      return;
    }
    setState(() {
      if (isApplicant) {
        _sendingApplicant = true;
      } else {
        _sendingCo = true;
      }
    });
    try {
      final appId =
          int.tryParse(widget.applicationId.trim()) ?? widget.applicationId;
      final res = await _repo.resendConsentLink(
        applicationId: appId,
        consentIds: widget.consentIds,
        // Flat body: { applicationId, consentIds, mobileNumber, applicantType }
        // for the person whose "Resend Link" was tapped.
        applicantType: applicantType,
        mobileNumber: mobile,
      );
      if (!mounted) return;
      final ok =
          res is Map && (res['success'] == true || res['status'] == true);
      final msg = _serverMsg(res);
      _snack(
        msg ??
            (ok
                ? 'Consent link resent'
                : 'Could not resend the link. Please try again.'),
        ok: ok,
      );
    } on ApiException catch (e) {
      if (mounted) _snack(e.message);
    } catch (_) {
      if (mounted) _snack('Something went wrong. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          if (isApplicant) {
            _sendingApplicant = false;
          } else {
            _sendingCo = false;
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppFlowScaffold(
      title: 'Consent Link Sent',
      stepText: 'Step 3 of 5',
      // Exit (outlined) + Proceed (gradient). Proceed filhal DISABLED
      // (enabled:false → dimmed + non-tappable); Exit returns to Home.
      bottomBar: InteractionBottomBar(
        actionLabel: 'Proceed',
        enabled: false,
        onAction: () {},
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          const SizedBox(height: 8),
          const Center(
            child: SuccessBadge(
              child: AppIcon(AppAssets.consentLink, size: 36),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Consent link has been sent to applicant and co-applicant '
              'mobile number',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, height: 1.4, color: p.title),
            ),
          ),
          const SizedBox(height: 18),
          // Sent To card.
          FlowCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sent To',
                    style: TextStyle(fontSize: 13, color: p.subtitle)),
                const SizedBox(height: 8),
                _sentToLine(
                    context,
                    widget.applicantMobile.isNotEmpty
                        ? widget.applicantMobile
                        : '—',
                    'Applicant'),
                const SizedBox(height: 6),
                _sentToLine(
                    context,
                    widget.coApplicantMobile.isNotEmpty
                        ? widget.coApplicantMobile
                        : '—',
                    'Co-Applicant'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Links + resend.
          FlowCard(
            child: Column(
              children: [
                _linkRow(
                  context,
                  'Applicant Link',
                  'APPLICANT',
                  _sendingApplicant,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1, color: p.fieldBorder),
                ),
                _linkRow(
                  context,
                  'Co-Applicant Link',
                  'CO_APPLICANT',
                  _sendingCo,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sentToLine(BuildContext context, String mobile, String who) {
    final p = context.palette;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: mobile,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: p.title),
          ),
          TextSpan(
            text: '  ($who)',
            style: TextStyle(fontSize: 13.5, color: p.subtitle),
          ),
        ],
      ),
    );
  }

  Widget _linkRow(
    BuildContext context,
    String label,
    String applicantType,
    bool sending,
  ) {
    final p = context.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: p.title)),
              const SizedBox(height: 3),
              Text('Dummylink',
                  style: const TextStyle(
                      fontSize: 13.5,
                      color: AppColors.statusBlue,
                      decoration: TextDecoration.underline,
                      decorationColor: AppColors.statusBlue)),
            ],
          ),
        ),
        // While resending → small spinner; otherwise an always-tappable
        // "Resend Link" that re-fires /consent/resend-link for this type.
        sending
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.primary),
              )
            : GestureDetector(
                onTap: () => _resend(applicantType),
                behavior: HitTestBehavior.opaque,
                child: const Text('Resend Link',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
              ),
      ],
    );
  }
}
