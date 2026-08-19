import 'package:flutter/material.dart';
import '../../core/device/app_device.dart';
import '../../data/models/disbursement_status.dart';
import '../../data/models/lead_item.dart';
import '../../data/repositories/application_repository.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_colors.dart';
import 'application_flow_ui.dart';
import 'post_disbursal_conditions_screen.dart';

/// Disbursement Status — loads `POST /application/disbursement-status` ({ leadId })
/// and renders Pending vs Success from the response: title/subtitle, summary,
/// the "Loan Account Activated" banner, and the Proceed-to-Post-Disbursal button
/// (shown only when `canProceedToPostDisbursal` is true).
class DisbursementStatusScreen extends StatefulWidget {
  const DisbursementStatusScreen({super.key, required this.lead});
  final LeadItem lead;

  @override
  State<DisbursementStatusScreen> createState() =>
      _DisbursementStatusScreenState();
}

class _DisbursementStatusScreenState extends State<DisbursementStatusScreen> {
  final _repo = ApplicationRepository();
  bool _loading = true;
  String? _error;
  DisbursementStatus? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final leadId = int.tryParse(widget.lead.id.trim()) ?? widget.lead.id;
      final data = await _repo.getDisbursementStatus(leadId: leadId);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('ApiException: ', '');
        _loading = false;
      });
    }
  }

  static String _dash(String v) => v.trim().isEmpty ? '—' : v.trim();

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AppFlowScaffold(
        title: 'Disbursement Status',
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return AppFlowScaffold(
        title: 'Disbursement Status',
        body: _ErrorView(message: _error!, onRetry: _load),
      );
    }
    final p = context.palette;
    final d = _data!;
    final disbursed = d.isDisbursed;
    final s = d.summary;
    return AppFlowScaffold(
      title: 'Disbursement Status',
      bottomBar: d.canProceedToPostDisbursal
          // Can proceed → Proceed to Post-Disbursal + Exit.
          ? _SuccessBottomBar(
              onProceed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PostDisbursalConditionsScreen(
                    lead: widget.lead,
                    stageId: d.stageId,
                    applicationId: d.applicationId.isNotEmpty
                        ? d.applicationId
                        : d.summary.applicationId,
                  ),
                ),
              ),
            )
          // Not yet → Exit only.
          : _ExitBottomBar(
              onExit: () => Navigator.of(context)
                  .pushNamedAndRemoveUntil(AppRoutes.home, (r) => false),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
        children: [
          Center(child: _StatusBadge(disbursed: disbursed)),
          const SizedBox(height: 20),
          Center(
            child: Text(
              d.title.isNotEmpty
                  ? d.title
                  : (disbursed
                      ? 'Loan Disbursed Successfully!'
                      : 'Disbursement Approval Pending'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                height: 1.25,
                fontWeight: FontWeight.w800,
                color: disbursed ? AppColors.success : p.title,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              d.subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.4, color: p.subtitle),
            ),
          ),
          const SizedBox(height: 22),
          FlowCard(
            heading: 'Disbursement Summary',
            child: Column(
              children: [
                // DetailRow(
                //     label: 'Application No',
                //     value: _dash(s.applicationNo.toUpperCase())),
                DetailRow(
                    label: 'Applicant Name', value: _dash(s.applicantName)),
                DetailRow(
                    label: 'OEM/Dealer Name', value: _dash(s.oemDealerName)),
                DetailRow(
                  label: 'Disbursement Status',
                  valueWidget: Align(
                    alignment: Alignment.centerLeft,
                    child: disbursed
                        ? StatusPill(
                            text: s.disbursementStatus.isEmpty
                                ? 'Success'
                                : s.disbursementStatus)
                        : StatusPill(
                            text: s.disbursementStatus.isEmpty
                                ? 'Pending'
                                : s.disbursementStatus,
                            color: AppColors.chartProgress,
                            icon: Icons.hourglass_top),
                  ),
                ),
                DetailRow(
                  label: 'Loan ID (LMS Reference)',
                  valueWidget: Text(
                    _dash(s.loanId),
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      fontWeight: FontWeight.w700,
                      color: disbursed ? AppColors.success : p.title,
                    ),
                  ),
                ),
                DetailRow(
                    label: 'Disbursement Date & Time',
                    value: _dash(s.disbursementDateTime)),
              ],
            ),
          ),
          if (d.loanAccountActivated) ...[
            const SizedBox(height: 16),
            const _AccountActivatedBanner(),
          ],
        ],
      ),
    );
  }
}

/// Error + Retry view (load failed).
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: p.subtitle),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: p.subtitle)),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Retry',
                  style: TextStyle(color: AppColors.primary)),
            ),
          ],
        ),
      ),
    );
  }
}

/// The big circular badge — green check when disbursed, orange "!" when pending.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.disbursed});
  final bool disbursed;

  @override
  Widget build(BuildContext context) {
    if (disbursed) return const SuccessBadge(bigCheck: true);
    return Container(
      width: 92,
      height: 92,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.purple.withValues(alpha: 0.10),
      ),
      child: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.chartProgress,
        ),
        child: const Icon(Icons.priority_high, size: 30, color: Colors.white),
      ),
    );
  }
}

/// Green "Loan Account Activated" confirmation banner (success only).
class _AccountActivatedBanner extends StatelessWidget {
  const _AccountActivatedBanner();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.success,
            ),
            child: const Icon(Icons.check, size: 20, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Loan Account Activated',
                    style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.success)),
                const SizedBox(height: 2),
                Text('Loan account is now active.',
                    style: TextStyle(fontSize: 12.5, color: p.subtitle)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Stacked bottom bar: gradient "Proceed to Post-Disbursal Conditions" over an
/// outlined "Exit" (→ Home). Used in the success state.
class _SuccessBottomBar extends StatelessWidget {
  const _SuccessBottomBar({required this.onProceed});
  final VoidCallback onProceed;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + AppDevice.bottomNavGap),
      decoration: BoxDecoration(
        color: p.cardBg,
        border: Border(top: BorderSide(color: p.fieldBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // DecoratedBox(
            //   decoration: BoxDecoration(
            //     gradient: AppColors.buttonGradient,
            //     borderRadius: BorderRadius.circular(12),
            //   ),
            //   child: ElevatedButton(
            //     onPressed: onProceed,
            //     style: ElevatedButton.styleFrom(
            //       minimumSize: const Size.fromHeight(50),
            //       backgroundColor: Colors.transparent,
            //       shadowColor: Colors.transparent,
            //       shape: RoundedRectangleBorder(
            //           borderRadius: BorderRadius.circular(12)),
            //     ),
            //     child: const Text('Proceed to Post-Disbursal Conditions',
            //         style: TextStyle(
            //             fontSize: 15,
            //             fontWeight: FontWeight.w700,
            //             color: Colors.white)),
            //   ),
            // ),
            const SizedBox(height: 10),
            _ExitButton(
              onExit: () => Navigator.of(context)
                  .pushNamedAndRemoveUntil(AppRoutes.home, (r) => false),
            ),
          ],
        ),
      ),
    );
  }
}

/// Single full-width outlined "Exit" bottom bar (pending state).
class _ExitBottomBar extends StatelessWidget {
  const _ExitBottomBar({required this.onExit});
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + AppDevice.bottomNavGap),
      decoration: BoxDecoration(
        color: p.cardBg,
        border: Border(top: BorderSide(color: p.fieldBorder)),
      ),
      child: SafeArea(top: false, child: _ExitButton(onExit: onExit)),
    );
  }
}

/// Shared outlined "Exit" button.
class _ExitButton extends StatelessWidget {
  const _ExitButton({required this.onExit});
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return OutlinedButton(
      onPressed: onExit,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        side: BorderSide(color: p.fieldBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text('Exit',
          style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w700, color: p.title)),
    );
  }
}
