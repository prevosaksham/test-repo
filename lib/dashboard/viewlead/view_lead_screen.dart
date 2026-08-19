import 'package:flutter/material.dart';
import '../../data/models/lead_details.dart';
import '../../data/models/lead_item.dart';
import '../../data/repositories/lead_repository.dart';
import '../../theme/app_colors.dart';
import '../application/generated_document_card.dart';
import 'view_lead_details_tab.dart';
import 'view_lead_sections.dart';
import 'view_lead_timeline_tab.dart';

/// View Lead — read-only application view opened from My Leads → "View".
/// Loads `POST /rm/lead-details` for the lead and shows two tabs: Timeline (the
/// stages stepper + per-stage info) and Application Details (applicant /
/// co-applicant captured data + uploaded documents).
class ViewLeadScreen extends StatefulWidget {
  const ViewLeadScreen({super.key, required this.lead});
  final LeadItem lead;

  @override
  State<ViewLeadScreen> createState() => _ViewLeadScreenState();
}

class _ViewLeadScreenState extends State<ViewLeadScreen> {
  final LeadRepository _repo = LeadRepository();

  int _tab = 0; // 0 = Timeline, 1 = Application Details
  // Which Application-Details accordion is open (only ONE at a time). Section
  // ids: 0 = Application & KYC (open by default) … 5 = Post Disbursement. null =
  // all collapsed.
  int? _openSection = 0;
  bool _loading = true;
  String? _error;
  LeadDetails? _details;

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
      final d = await _repo.getLeadDetails(leadId: widget.lead.id);
      if (!mounted) return;
      setState(() {
        _details = d;
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
        title: Text('Application Details',
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700, color: p.title)),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _errorView(_error!);
    }
    final d = _details;
    if (d == null) return _errorView('No details found');

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _header(d),
        const SizedBox(height: 16),
        _tabs(),
        const SizedBox(height: 16),
        if (_tab == 0)
          ViewLeadTimelineTab(stages: d.timeline)
        else
          ..._detailSections(d),
      ],
    );
  }

  // The Application Details tab — a numbered accordion list where only ONE
  // section is open at a time (see [_openSection]). Section 1 (Application &
  // KYC) is open by default.
  List<Widget> _detailSections(LeadDetails d) {
    return [
      ViewLeadDetailsTab(
        applicant: d.applicant,
        coApplicant: d.coApplicant,
        applicantDocs: d.applicantDocs,
        coApplicantDocs: d.coApplicantDocs,
        bankDetails: d.bankDetails,
        sectionTitle: '1. ${d.applicationKycTitle}',
        expanded: _openSection == 0,
        onToggle: () => _toggleSection(0),
      ),
      if (d.loanApproval != null) ...[
        const SizedBox(height: 12),
        LeadAccordion(
          title: '2. ${d.loanApproval!.title}',
          expanded: _openSection == 1,
          onToggle: () => _toggleSection(1),
          child: LoanApprovalSection(data: d.loanApproval!),
        ),
      ],
      if (d.generatedDocuments.isNotEmpty) ...[
        const SizedBox(height: 12),
        LeadAccordion(
          title: '3. ${d.documentsTitle}',
          expanded: _openSection == 2,
          onToggle: () => _toggleSection(2),
          child: Column(
            children: [
              for (var i = 0; i < d.generatedDocuments.length; i++) ...[
                GeneratedDocumentCard(
                  doc: d.generatedDocuments[i],
                  applicationId: d.applicationId,
                  greenWhenGenerated: true,
                ),
                if (i != d.generatedDocuments.length - 1)
                  const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ],
      if (d.fieldInvestigation != null) ...[
        const SizedBox(height: 12),
        LeadAccordion(
          title: '4. ${d.fieldInvestigation!.title}',
          expanded: _openSection == 3,
          onToggle: () => _toggleSection(3),
          child: FieldInvestigationSection(data: d.fieldInvestigation!),
        ),
      ],
      if (d.preDisbursal != null) ...[
        const SizedBox(height: 12),
        LeadAccordion(
          title: '5. ${d.preDisbursal!.title}',
          expanded: _openSection == 4,
          onToggle: () => _toggleSection(4),
          child: PreDisbursalSection(data: d.preDisbursal!),
        ),
      ],
      if (d.postDisbursement != null) ...[
        const SizedBox(height: 12),
        LeadAccordion(
          title: '6. ${d.postDisbursement!.title}',
          expanded: _openSection == 5,
          onToggle: () => _toggleSection(5),
          child: PostDisbursementSection(data: d.postDisbursement!),
        ),
      ],
    ];
  }

  // Open the tapped section and close the rest; tapping the open one closes it.
  void _toggleSection(int id) =>
      setState(() => _openSection = _openSection == id ? null : id);

  Widget _errorView(String message) {
    final p = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 44, color: p.subtitle),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: p.subtitle)),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _load,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Retry',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: AppColors.primary)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(LeadDetails d) {
    final p = context.palette;
    final statusColor = _hexColor(d.leadStatus.colorHex, AppColors.purple);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.fieldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row(
          //   crossAxisAlignment: CrossAxisAlignment.start,
          //   children: [
          //     Expanded(
          //       child: Column(
          //         crossAxisAlignment: CrossAxisAlignment.start,
          //         children: [
          //           Text('Application ID',
          //               style: TextStyle(fontSize: 12.5, color: p.subtitle)),
          //           const SizedBox(height: 3),
          //           Text(d.applicationId.isEmpty ? '—' : d.applicationId,
          //               style: const TextStyle(
          //                   fontSize: 18,
          //                   fontWeight: FontWeight.w700,
          //                   color: AppColors.purple)),
          //         ],
          //       ),
          //     ),
          //     if (d.leadStatus.displayName.isNotEmpty)
          //       _pill(d.leadStatus.displayName, statusColor),
          //   ],
          // ),
          // Application number on the left + current status (light-green pill)
          // on the right. Shown only when the API sends them.
          if (d.applicationNo.isNotEmpty || d.currentStatus.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                //if (d.applicationNo.isNotEmpty)
                  Expanded(
                      child: _miniField('Application No', d.applicationNo.isNotEmpty ? d.applicationNo.toUpperCase() : "")),
                if (d.applicationNo.isNotEmpty && d.currentStatus.isNotEmpty)
                  const SizedBox(width: 12),
                if (d.currentStatus.isNotEmpty)
                  _pill(
                    d.currentStatusLabel,
                    d.currentStatusLabel.toLowerCase() == 'rejected'
                        ? Colors.red
                        : AppColors.success,
                  ), 
              ],
            ),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: p.fieldBorder),
          ),
          Text(d.name.isEmpty ? '—' : d.name,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: p.title)),
          const SizedBox(height: 8),
          Row(
            children: [
              if (d.mobile.isNotEmpty) ...[
                Icon(Icons.call, size: 16, color: p.subtitle),
                const SizedBox(width: 5),
                Text(d.mobile,
                    style: TextStyle(fontSize: 13.5, color: p.subtitle)),
                const SizedBox(width: 14),
              ],
              if (d.location.isNotEmpty) ...[
                Icon(Icons.location_on_outlined, size: 17, color: p.subtitle),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(d.location,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13.5, color: p.subtitle)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniField(String label, String value) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11.5, color: p.subtitle)),
        const SizedBox(height: 3),
        Text(value,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: p.title)),
      ],
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 12.5, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _tabs() {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: p.cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.fieldBorder),
      ),
      child: Row(
        children: [
          _tabBtn('Timeline', 0),
          _tabBtn('Application Details', 1),
        ],
      ),
    );
  }

  Widget _tabBtn(String label, int index) {
    final p = context.palette;
    final selected = _tab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = index),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? AppColors.purple : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : p.subtitle)),
        ),
      ),
    );
  }
}

/// Parse "#RRGGBB" (or "#AARRGGBB") into a Color, falling back to [fallback].
Color _hexColor(String hex, Color fallback) {
  var h = hex.trim().replaceFirst('#', '');
  if (h.isEmpty) return fallback;
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  return v == null ? fallback : Color(v);
}
