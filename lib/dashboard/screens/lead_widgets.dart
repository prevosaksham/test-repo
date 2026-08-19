import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/models/lead_item.dart';
import '../../theme/app_colors.dart';
import '../application/disbursement_status_screen.dart';
import '../application/esign_pending_screen.dart';
import '../application/financial_approval_screen.dart';
import '../application/loan_approved_screen.dart';
import '../application/pre_disbursal_requirements_screen.dart';
import '../viewlead/lead_details_screen.dart';
import '../viewlead/view_lead_screen.dart';
import 'lead_interaction_screen.dart';

/// Shared list widgets used by both the My Leads tab and the All Leads
/// ("View All") screen — the lead card, the status filter row, and the
/// centered message/retry placeholder.

/// Parse a "#RRGGBB" (or "#AARRGGBB") hex into a Color, else [fallback].
Color _hexColor(String hex, Color fallback) {
  var h = hex.replaceAll('#', '').trim();
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  return v == null ? fallback : Color(v);
}

/// One row in the status-filter dialog.
class LeadFilterRow extends StatelessWidget {
  const LeadFilterRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        color: selected
            ? AppColors.purple.withValues(alpha: 0.08)
            : Colors.transparent,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppColors.purple : p.title,
                ),
              ),
            ),
            if (selected)
              const Icon(Icons.check, size: 18, color: AppColors.purple),
          ],
        ),
      ),
    );
  }
}

class LeadCard extends StatelessWidget {
  const LeadCard({super.key, required this.lead});
  final LeadItem lead;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    // Manage button routing:
    //  1. no Application ID + not loan-approved → Customer Interaction flow
    //  2. Application ID present + not loan-approved → Financial Approval (pending)
    //  3. Application ID present + loan-approved → Loan Approved
    // The Manage button is disabled for rejected leads (unchanged).
    final bool isRejected = lead.status.value.toUpperCase().contains('REJECTED');
    final bool hasApplication = (lead.applicationNo.isNotEmpty && lead.isLoanApproved == false);
    final bool isLoanApproved = (lead.applicationNo.isNotEmpty && (lead.isLoanApproved == true && lead.isFiDone == false));
    // Common base for the post-FI stages: application present, loan approved, FI done.
    final bool postFi = lead.applicationNo.isNotEmpty &&
        lead.isLoanApproved == true &&
        lead.isFiDone == true;
    // E-sign page ("eSign Pending" / "eSign Success"):
    //  • e-sign NOT done                                   → Pending
    //  • e-sign done but Disbursement questions NOT answered → Success (answer there)
    final bool isEsign = postFi &&
        (lead.isEsignDone == false || lead.isDisbursementQuestionsDone == false);
    // Pre-Disbursal Uploads: e-sign + Disbursement questions done, but the
    // pre-disbursal uploads are not done yet.
    final bool isPreDisbursal = postFi &&
        lead.isEsignDone == true &&
        lead.isDisbursementQuestionsDone == true &&
        lead.isPreDisbursementDone == false;
    // Disbursement Status: pre-disbursal uploads done (or final disbursement done).
    final bool isDisbursement = postFi &&
        lead.isEsignDone == true &&
        ((lead.isDisbursementQuestionsDone == true &&
                lead.isPreDisbursementDone == true) ||
            lead.isDisbursmentDone == true);

    Widget manageTarget() {
      if (hasApplication) return FinancialApprovalScreen(lead: lead);
      if (isLoanApproved) return LoanApprovedScreen(lead: lead);
      // Pre-disbursal uploads done (or disbursed) → Disbursement Status.
      if (isDisbursement) return DisbursementStatusScreen(lead: lead);
      // e-sign + Disbursement questions done, uploads pending → Pre-Disbursal.
      if (isPreDisbursal) return PreDisbursalRequirementsScreen(lead: lead);
      // e-sign pending, OR e-sign done but Disbursement questions not answered →
      // E-sign page (shows "eSign Success" so the RM answers the questions).
      if (isEsign) return ESignPendingScreen(lead: lead);
      return LeadInteractionScreen(lead: lead);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.fieldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                // When an Application ID exists, show it (labelled) with the
                // Lead ID below it; otherwise just show the Lead ID in bold
                // (as it was before).
                child: lead.applicationNo.isNotEmpty
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Application ID',
                            style: TextStyle(fontSize: 12, color: p.subtitle),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            lead.applicationNo,
                            style: const TextStyle(
                              fontSize: 18,
                              height: 21 / 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.purple,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Text(
                                'Lead ID: ${lead.leadNo.isEmpty ? '—' : lead.leadNo}',
                                style:
                                    TextStyle(fontSize: 13, color: p.subtitle),
                              ),
                              const SizedBox(width: 6),
                              // Eye opens the read-only Lead Details page.
                              GestureDetector(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          LeadDetailsScreen(lead: lead),
                                    ),
                                  );
                                },
                                behavior: HitTestBehavior.opaque,
                                child: const Padding(
                                  padding: EdgeInsets.all(2),
                                  child: Icon(
                                    Icons.remove_red_eye_outlined,
                                    size: 18,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Lead ID',
                            style: TextStyle(fontSize: 12, color: p.subtitle),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            lead.leadNo.isEmpty ? '—' : lead.leadNo,
                            style: const TextStyle(
                              fontSize: 18,
                              height: 21 / 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.purple,
                            ),
                          ),
                        ],
                      ),
              ),
              if (lead.status.displayName.isNotEmpty)
                _StatusBadge(status: lead.status),
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
              height: 19 / 16,
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
                style: TextStyle(
                  fontSize: 14,
                  height: 16 / 14,
                  color: p.subtitle,
                ),
              ),
              if (lead.location.isNotEmpty) ...[
                const SizedBox(width: 14),
                Icon(Icons.location_on_outlined, size: 17, color: p.subtitle),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    lead.location,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      height: 16 / 14,
                      color: p.subtitle,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'Next Activity: ',
                        style: TextStyle(
                          fontSize: 13,
                          height: 15 / 13,
                          color: p.subtitle,
                        ),
                      ),
                      TextSpan(
                        text: lead.nextActivity,
                        style: TextStyle(
                          fontSize: 13,
                          height: 15 / 13,
                          color: p.title,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),

              _ManageButton(
                // Disabled only for rejected leads (unchanged). Otherwise routes
                // by application/loan-approved state via manageTarget().
                enabled: !isRejected,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => manageTarget(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _ViewButton(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ViewLeadScreen(lead: lead),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final LeadStatusInfo status;

  @override
  Widget build(BuildContext context) {
    final color = _hexColor(status.colorHex, AppColors.purple);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon(Icons.check_circle, size: 16, color: color),
          // const SizedBox(width: 5),
          Text(
            status.displayName,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ManageButton extends StatelessWidget {
  const _ManageButton({required this.enabled, this.onTap});
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: GestureDetector(
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                onTap?.call();
              }
            : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            gradient: AppColors.buttonGradient,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            'Manage',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _ViewButton extends StatelessWidget {
  const _ViewButton({this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.primary),
        ),
        child: const Text(
          'View',
          style: TextStyle(
            color: AppColors.primary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// Centered message + optional Retry (loading-failure / empty placeholder).
class LeadMessage extends StatelessWidget {
  const LeadMessage({super.key, required this.text, this.onRetry});
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: p.subtitle, fontSize: 14),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ],
      ),
    );
  }
}
