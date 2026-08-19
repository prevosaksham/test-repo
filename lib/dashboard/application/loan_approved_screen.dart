import 'package:flutter/material.dart';
import '../../data/models/financial_approval.dart';
import '../../data/models/lead_item.dart';
import '../../data/repositories/lead_repository.dart';
import '../../theme/app_colors.dart';
import '../widgets/interaction_ui.dart';
import 'application_flow_ui.dart';
import 'field_investigation_screen.dart';
import 'generated_document_card.dart';

/// Financial Approval — "Loan Approved" state. Driven by
/// `POST /rm/financial-approval` ({ applicationId }): applicant + loan summary
/// and the auto-generated documents (each Preview/Download-able, with an e-sign
/// status).
class LoanApprovedScreen extends StatefulWidget {
  const LoanApprovedScreen({super.key, required this.lead});
  final LeadItem lead;

  @override
  State<LoanApprovedScreen> createState() => _LoanApprovedScreenState();
}

class _LoanApprovedScreenState extends State<LoanApprovedScreen> {
  final _repo = LeadRepository();
  bool _loading = true;
  String? _error;
  FinancialApproval? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }
  Future<void> _load() async {
    final appId = widget.lead.id;
    if (appId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Application ID not available for this lead.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {   
      final data = await _repo.getFinancialApproval(leadId: appId);
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

  @override
  Widget build(BuildContext context) {
    // The static structure (section labels/headings) renders immediately; a
    // centered loader overlays it while the values load, then they fill in.
    return AppFlowScaffold(
      title: 'Financial Approval',
      bottomBar: _loading || _error != null
          ? null
          : InteractionBottomBar(
              actionLabel: 'Proceed',
              onAction: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => FieldInvestigationScreen(lead: widget.lead),
                ),
              ),
            ),
      body: _error != null
          ? _ErrorView(message: _error!, onRetry: _load)
          : Stack(
              children: [
                _ApprovalBody(data: _data, leadId: widget.lead.id),
                if (_loading)
                  const Positioned.fill(
                    child: ColoredBox(
                      color: Color(0x55000000),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
              ],
            ),
    );
  }
}

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

class _ApprovalBody extends StatelessWidget {
  const _ApprovalBody({required this.data, required this.leadId});
  // Nullable — the static labels/structure render immediately; the values
  // (and documents) fill in once [data] arrives.
  final FinancialApproval? data;
  final String leadId;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final a = data?.applicant;
    final l = data?.loan;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        _LoanApprovedBanner(info: data?.loanApproved),
        const SizedBox(height: 16),

        // Applicant Details
        FlowCard(
          heading: 'Applicant Details',
          child: Column(
            children: [
              DetailRow(
                  label: 'Loan ID',
                  value: _dash(l?.loanId ?? '')),
              DetailRow(
                  label: 'Applicant Name',
                  value: _dash(a?.applicantName ?? '')),
              DetailRow(
                  label: 'Mobile Number',
                  value: _dash(a?.mobileNumber ?? '')),
              DetailRow(label: 'PAN', value: _dash(a?.pan ?? '')),
              DetailRow(
                  label: 'Date & Time', value: _dash(a?.dateTime ?? '')),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Loan Details
        FlowCard(
          heading: 'Loan Details',
          child: Column(
            children: [
              DetailRow(label: 'OEM/ Dealer', value: _dash(l?.oemDealer ?? '')),
              DetailRow(
                  label: 'Vehicle Name', value: _dash(l?.vehicleName ?? '')),
              DetailRow(
                  label: 'Vehicle Category',
                  value: _dash(l?.vehicleCategory ?? '')),
              DetailRow(
                  label: 'Vehicle Amount', value: _inr(l?.vehicleAmount)),
              DetailRow(label: 'Loan Amount', value: _inr(l?.loanAmount)),
              DetailRow(
                  label: 'Tenure',
                  value: l?.tenure == null
                      ? '—'
                      : '${_num(l?.tenure)} Months'),
              DetailRow(
                  label: 'Rate of Interest',
                  value: _percent(l?.rateOfInterest)),
              DetailRow(label: 'Margin', value: _inr(l?.margin)),
              DetailRow(label: 'Subsidy', value: _percent(l?.subsidy)),
              DetailRow(label: 'EMI Amount', value: _inr(l?.emiAmount)),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Generated Documents header — rounded card like the other sections.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: p.cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p.fieldBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Generated Documents',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: p.title)),
              const SizedBox(height: 4),
              Text(
                'The following documents are generated and ready for review.',
                style: TextStyle(fontSize: 13, color: p.subtitle),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        if (data == null)
          const SizedBox(height: 4) // loading → values fill in shortly
        else if (data!.documents.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text('No documents generated yet',
                  style: TextStyle(fontSize: 13.5, color: p.subtitle)),
            ),
          )
        else
          for (final d in data!.documents) ...[
            GeneratedDocumentCard(doc: d, applicationId: a?.id ?? ''),
            const SizedBox(height: 12),
          ],
        const SizedBox(height: 4),

        const _ESignNote(),
      ],
    );
  }

  static String _dash(String v) => v.trim().isEmpty ? '—' : v;

  // "3,73,000" → Indian digit grouping.
  static String _group(String intPart) {
    if (intPart.length <= 3) return intPart;
    final last3 = intPart.substring(intPart.length - 3);
    final rest = intPart.substring(0, intPart.length - 3);
    final grouped =
        rest.replaceAllMapped(RegExp(r'\B(?=(\d{2})+(?!\d))'), (m) => ',');
    return '$grouped,$last3';
  }

  static String _num(num? v) {
    if (v == null) return '—';
    if (v == v.roundToDouble()) return _group(v.toInt().toString());
    final f = v.toStringAsFixed(2);
    final parts = f.split('.');
    return '${_group(parts[0])}.${parts[1]}';
  }

  static String _inr(num? v) => v == null ? '—' : '₹ ${_num(v)}';

  static String _percent(num? v) =>
      v == null ? '—' : '${v.toStringAsFixed(v == v.roundToDouble() ? 2 : 2)}%';
}

/// Green success banner at the top of the page.
class _LoanApprovedBanner extends StatelessWidget {
  const _LoanApprovedBanner({required this.info});
  final LoanApprovedInfo? info;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                Text(
                    (info?.title.isEmpty ?? true)
                        ? 'Loan Approved'
                        : info!.title,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.success)),
                const SizedBox(height: 3),
                Text(
                  (info?.message.isEmpty ?? true)
                      ? 'The loan has been approved. Documents are generated '
                          'and ready for next step.'
                      : info!.message,
                  style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: context.palette.subtitle),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Grey footer note about e-sign.
class _ESignNote extends StatelessWidget {
  const _ESignNote();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.fieldBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: p.subtitle.withValues(alpha: 0.85),
            ),
            child: const Icon(Icons.info_outline, size: 17, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Documents are generated but not yet signed. After final approval, '
              'documents will be sent for E-sign.',
              style: TextStyle(fontSize: 12.5, height: 1.4, color: p.subtitle),
            ),
          ),
        ],
      ),
    );
  }
}
