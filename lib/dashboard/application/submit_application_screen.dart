import 'package:flutter/material.dart';
import '../../core/constants/app_assets.dart';
import '../../core/device/app_device.dart';
import '../../core/widgets/app_icon.dart';
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
import '../../widgets/app_buttons.dart';
import 'application_flow_ui.dart';
import 'view_application_screen.dart';

/// Step 5 of 5 — review summary (dynamic, from `/application/details`) and
/// submit the application.
class SubmitApplicationScreen extends StatefulWidget {
  const SubmitApplicationScreen({super.key, required this.lead});
  final LeadItem lead;

  @override
  State<SubmitApplicationScreen> createState() =>
      _SubmitApplicationScreenState();
}

class _SubmitApplicationScreenState extends State<SubmitApplicationScreen> {
  final ApplicationRepository _repo = ApplicationRepository();
  ApplicationDetails? _details;
  bool _loading = true; // /application/details fetch in progress
  bool _submitting = false; // /application/submit call in progress

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await _repo.getApplicationDetails(leadId: widget.lead.id);
      if (mounted) setState(() => _details = d);
    } catch (_) {/* leave blank */} finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  // "2026-06-20T15:00:47Z" → "20 Jun 2026". Empty/unparseable → as-is/blank.
  String _fmtCreatedOn(String raw) {
    if (raw.trim().isEmpty) return '';
    final d = DateTime.tryParse(raw);
    if (d == null) return raw;
    final l = d.toLocal();
    return '${l.day.toString().padLeft(2, '0')} ${_months[l.month - 1]} ${l.year}';
  }

  // application.kyc ("COMPLETED") → a friendly "KYC Completed" label. Falls back
  // to application.status, else "KYC Completed".
  String _kycLabel() {
    final kyc = _details?.kyc.trim() ?? '';
    if (kyc.isNotEmpty) {
      final s = kyc.toLowerCase();
      return 'KYC ${s[0].toUpperCase()}${s.substring(1)}'; // "KYC Completed"
    }
    final status = _details?.status.trim() ?? '';
    return status.isNotEmpty ? status : 'KYC Completed';
  }

  void _toHome(BuildContext context) => Navigator.of(context)
      .pushNamedAndRemoveUntil(AppRoutes.home, (r) => false);

  // Submit → POST /application/submit (all data dynamic), then home on success.
  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final rawAppId = _details?.applicationId ?? '';
      final appId = int.tryParse(rawAppId.trim()) ?? rawAppId;
      final leadId = int.tryParse(widget.lead.id.trim()) ?? widget.lead.id;
      final stage = await _resolveSubmitStage(); // Application Submitted stage
      final body = {
        'applicationId': appId,
        'leadId': leadId,
        'stageId': stage.id,
        'stageType': stage.type,
        'status': 'submitted',
      };
      debugPrint('submit-application body: $body');
      final res = await _repo.submitApplication(
        applicationId: appId,
        leadId: leadId,
        stageId: stage.id,
        stageType: stage.type,
        status: 'submitted',
      );
      debugPrint('submit-application response: $res');
      if (!mounted) return;
      final ok = res is Map && (res['success'] == true || res['status'] == true);
      final msg = (res is Map &&
              res['message'] is String &&
              (res['message'] as String).trim().isNotEmpty)
          ? (res['message'] as String).trim()
          : null;
      if (!ok) {
        AppToast.show(context, msg ?? 'Could not submit. Please try again.',
            type: ToastType.error);
        return;
      }
      // The submitted application number (response data.applicationNo).
      final data = res['data'] is Map
          ? Map<String, dynamic>.from(res['data'] as Map)
          : const <String, dynamic>{};
      final appNo = (data['applicationNo'] ?? '').toString();
      // Stop the button loader FIRST, then show the (non-dismissible) success
      // dialog — so the spinner doesn't keep spinning behind the dialog.
      setState(() => _submitting = false);
      await _showSubmittedDialog(
        msg ?? 'Application submitted successfully',
        applicationNo: appNo,
      );
    } on ApiException catch (e) {
      if (mounted) AppToast.show(context, e.message, type: ToastType.error);
    } catch (_) {
      if (mounted) {
        AppToast.show(context, 'Something went wrong. Please try again.',
            type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // Non-cancelable success dialog (back disabled, no barrier dismiss). OK →
  // Dashboard/Home. Shows the submitted application number when present.
  Future<void> _showSubmittedDialog(String message,
      {String applicationNo = ''}) async {
    final p = context.palette;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false, // hardware/back button disabled while open
        child: AlertDialog(
          backgroundColor: p.cardBg,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: AppColors.success),
                child: const Icon(Icons.check, size: 32, color: Colors.white),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: p.title),
              ),
              const SizedBox(height: 8),
              // Text(
              //   message,
              //   textAlign: TextAlign.center,
              //   style: TextStyle(fontSize: 13.5, height: 1.4, color: p.subtitle),
              // ),
              // Submitted application number (from response data.applicationNo).
              if (applicationNo.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Application No: ${applicationNo.toUpperCase()}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: p.title),
                ),
              ],
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            SizedBox(
              width: double.infinity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppColors.buttonGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(ctx).pop(); // close dialog
                    _toHome(context); // → dashboard
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('OK',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Application Submitted stage id + type: SharedPreferences (saved from
  // getPreview) → a fresh getPreview (cache it) → empty.
  Future<({String id, String type})> _resolveSubmitStage() async {
    StageItem? saved = await ApplicationStageStore.instance
        .stageByName(widget.lead.id, 'Application Submitted');
    if (saved == null || saved.id.isEmpty) {
      try {
        final preview = await LeadRepository().getPreview(leadId: widget.lead.id);
        await ApplicationStageStore.instance
            .save(widget.lead.id, preview.applicationStages);
        for (final s in preview.applicationStages) {
          if (s.stageName.trim().toLowerCase() == 'application submitted') {
            saved = s;
            break;
          }
        }
      } catch (_) {/* ignore */}
    }
    return (id: saved?.id ?? '', type: saved?.stageType ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppFlowScaffold(
      lockBack: true, // post-OTP — no going back; View Application keeps its back
      title: 'Submit Application',
      stepText: 'Step 5 of 5',
      bottomBar: Container(
        // Extra bottom gap for Android 15+ edge-to-edge nav bar (0 otherwise).
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + AppDevice.bottomNavGap),
        decoration: BoxDecoration(
          color: p.surface,
          border: Border(top: BorderSide(color: p.fieldBorder)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              PrimaryButton(
                label: 'Submit Application',
                loading: _submitting,
                onPressed: _loading ? null : _submit,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _toHome(context),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        side: BorderSide(color: p.fieldBorder),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('Exit',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: p.title)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              ViewApplicationScreen(lead: widget.lead),
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        side: const BorderSide(color: AppColors.primary),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('View Application',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              children: [
                const SizedBox(height: 8),
                const Center(
                  child: SuccessBadge(
                    child: AppIcon(AppAssets.submitApplication, size: 36),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text('Ready to submit',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: p.title)),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text('Please review and submit your application.',
                      style: TextStyle(fontSize: 13.5, color: p.subtitle)),
                ),
                const SizedBox(height: 18),
                FlowCard(
                  child: Column(
                    children: [
                      DetailRow(
                        label: 'Lead ID:',
                        value: widget.lead.leadNo.isNotEmpty
                            ? widget.lead.leadNo
                            : widget.lead.id,
                      ),
                      // Dynamic from /application/details (applicant object).
                      DetailRow(
                          label: 'Applicant Name:',
                          value: _details?.applicant?.fullName ?? ''),
                      DetailRow(
                          label: 'Mobile Number:',
                          value: _details?.applicant?.phoneNumber ?? ''),
                      // Dealer name from /application/details (dealer object).
                      DetailRow(
                          label: 'Dealer Name:',
                          value: _details?.dealerName ?? ''),
                      // DetailRow(
                      //     label: 'Created On:',
                      //     value: _fmtCreatedOn(_details?.createdAt ?? '')),
                      DetailRow(
                        label: 'Status:',
                        // KYC status from application.kyc (e.g. "COMPLETED" →
                        // "KYC Completed").
                        valueWidget: StatusPill(text: _kycLabel()),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
