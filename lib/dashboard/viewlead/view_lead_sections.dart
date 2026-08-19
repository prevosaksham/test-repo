import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/models/lead_details.dart';
import '../../data/repositories/lead_repository.dart';
import '../../theme/app_colors.dart';
import '../application/application_flow_ui.dart';
import 'view_lead_details_tab.dart';

/// A reusable collapsible section card for the View Lead → Application Details
/// accordion list (Loan Approval, Documents, Field Investigation, …). Matches
/// the "Application & KYC" card style; collapsed by default unless
/// [initiallyExpanded] is set.
class LeadAccordion extends StatefulWidget {
  const LeadAccordion({
    super.key,
    required this.title,
    required this.child,
    this.expanded,
    this.onToggle,
    this.initiallyExpanded = false,
  });
  final String title;
  final Widget child;
  // Controlled mode: when both [expanded] and [onToggle] are supplied the parent
  // owns the state (used by the top-level list so only ONE section is open at a
  // time). Otherwise the accordion keeps its own state (nested OCR tiles).
  final bool? expanded;
  final VoidCallback? onToggle;
  final bool initiallyExpanded;

  @override
  State<LeadAccordion> createState() => _LeadAccordionState();
}

class _LeadAccordionState extends State<LeadAccordion> {
  late bool _localExpanded = widget.initiallyExpanded;

  bool get _expanded => widget.expanded ?? _localExpanded;

  void _toggle() {
    if (widget.onToggle != null) {
      widget.onToggle!();
    } else {
      setState(() => _localExpanded = !_localExpanded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: p.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.fieldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: _toggle,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(widget.title,
                        style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: p.title)),
                  ),
                  Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 24,
                      color: p.subtitle),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(height: 1, color: p.fieldBorder),
            Padding(
              padding: const EdgeInsets.all(14),
              child: widget.child,
            ),
          ],
        ],
      ),
    );
  }
}

/// Loan Approval section content (inside a [LeadAccordion]) — read-only rows
/// from `applicationDetails.loanApproval`. Blank fields are skipped so no empty
/// "Label : —" is shown.
class LoanApprovalSection extends StatelessWidget {
  const LoanApprovalSection({super.key, required this.data});
  final LoanApproval data;

  @override
  Widget build(BuildContext context) {
    final d = data;
    final rows = <(String, String, String?)>[
      ('Applicant Name:', d.applicantName, '(as per PAN)'),
      ('Mobile Number:', d.mobileNumber, null),
      ('PAN:', d.panNumber, null),
      ('Date & Time:', d.dateTime, null),
      ('OEM / Dealer:', d.oemDealer, null),
      ('Vehicle Name:', d.vehicleName, null),
      ('Vehicle Category:', d.vehicleCategory, null),
      ('Ex-Showroom Price:', _money(d.exShowroomPrice), null),
      ('On-Road Price:', _money(d.onRoadPrice), null),
      ('Vehicle Amount:', _money(d.vehicleAmount), null),
      ('Insurance Amount:', _money(d.insuranceAmount), null),
      ('Subsidy:', _percent(d.subsidyPercentage), null),
      ('Loan Amount:', _money(d.loanAmount), null),
      ('Interest Rate:', _percent(d.interestRate), null),
      ('Processing Fee:', _money(d.processingFee), null),
      ('Down Payment:', _money(d.downpayment), null),
      ('Margin Amount:', _money(d.marginAmount), null),
      ('Tenure:', _tenure(d.tenure), null),
      ('EMI:', _money(d.emi), null),
      ('Employment Type:', _cap(d.employmentType), null),
      ('PD Status:', _cap(d.pdStatus), null),
      ('PD Date:', d.pdDate, null),
      ('PD Remarks:', d.pdRemarks, null),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (label, value, sub) in rows)
          if (value.trim().isNotEmpty)
            DetailRow(label: label, sublabel: sub, value: value),
      ],
    );
  }
}

/// Field Investigation section content — verification details + the FV selfie
/// documents (tappable to view the full image). Blank fields are skipped.
class FieldInvestigationSection extends StatelessWidget {
  const FieldInvestigationSection({super.key, required this.data});
  final FieldInvestigation data;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final d = data;
    final latLong = (d.latitude.trim().isNotEmpty && d.longitude.trim().isNotEmpty)
        ? '${d.latitude}, ${d.longitude}'
        : '';
    final rows = <(String, String, String?)>[
      ('Status:', _cap(d.status), null),
      ('Address Status:', _cap(d.addressMatchStatus), null),
      ('Verification Date:', d.verificationDate, null),
      ('Geo Address:', d.geoAddress, null),
      ('Lat / Long:', latLong, null),
      ('Remarks:', d.remarks, null),
      ('Reason:', d.reason, null),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (label, value, sub) in rows)
          if (value.trim().isNotEmpty)
            DetailRow(label: label, sublabel: sub, value: value),
        if (d.documents.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: p.fieldBorder),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 6, top: 4),
            child: Text('FV Selfies',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700, color: p.title)),
          ),
          const SizedBox(height: 6),
          DocThumbGrid(
            children: [for (final doc in d.documents) LeadDocTile(doc: doc)],
          ),
        ],
      ],
    );
  }
}

/// Pre-Disbursal Uploads section — the vehicle/asset summary + each OCR document
/// as a nested collapsible (extracted fields + a "View Document" PDF button when
/// available).
class PreDisbursalSection extends StatelessWidget {
  const PreDisbursalSection({super.key, required this.data});
  final PreDisbursal data;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final a = data.asset;
    final assetRows = <(String, String, String?)>[
      if (a != null) ...[
        ('Owner Name:', a.assetOwnerName, null),
        ('Vehicle Model:', a.vehicleModel, null),
        ('Model Number:', a.modelNumber, null),
        ('Manufacturer:', a.manufacturerName, null),
        ('Manufacturing Date:', a.manufacturingDate, null),
        ('Chassis Number:', a.chassisNumber, null),
        ('Motor Serial Number:', a.motorSerialNumber, null),
        ('Vehicle Type:', a.vehicleType, null),
      ],
    ];
    final hasAsset = assetRows.any((r) => r.$2.trim().isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasAsset) ...[
          _sectionLabel(context, 'Vehicle / Asset Details'),
          for (final (label, value, sub) in assetRows)
            if (value.trim().isNotEmpty)
              DetailRow(label: label, sublabel: sub, value: value),
        ],
        if (data.ocrData.isNotEmpty) ...[
          if (hasAsset)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1, color: p.fieldBorder),
            ),
          _sectionLabel(context, 'OCR Data'),
          const SizedBox(height: 6),
          for (var i = 0; i < data.ocrData.length; i++) ...[
            LeadAccordion(
              title: _ocrDocLabel(data.ocrData[i].documentCode),
              child: _OcrDocContent(doc: data.ocrData[i]),
            ),
            if (i != data.ocrData.length - 1) const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 4),
        child: Text(text,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: context.palette.title)),
      );
}

/// The expanded body of one OCR document — status + extracted scalar fields +
/// (when the source is a PDF) a "View Document" button.
class _OcrDocContent extends StatelessWidget {
  const _OcrDocContent({required this.doc});
  final OcrDoc doc;

  @override
  Widget build(BuildContext context) {
    final rows = _scalarRows(doc.extractedData);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (doc.ocrStatus.isNotEmpty)
          DetailRow(label: 'OCR Status:', value: _cap(doc.ocrStatus)),
        if (doc.verificationStatus.isNotEmpty)
          DetailRow(
              label: 'Verification Status:',
              value: _cap(doc.verificationStatus)),
        for (final (label, value) in rows)
          DetailRow(label: label, value: value),
        if (doc.hasPdf) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: _OcrPdfButton(url: doc.dataUri),
          ),
        ],
      ],
    );
  }
}

/// "View Document" — fetches the OCR document's PDF (dataUri) and opens it in the
/// in-app viewer. Spins while loading.
class _OcrPdfButton extends StatefulWidget {
  const _OcrPdfButton({required this.url});
  final String url;

  @override
  State<_OcrPdfButton> createState() => _OcrPdfButtonState();
}

class _OcrPdfButtonState extends State<_OcrPdfButton> {
  final LeadRepository _repo = LeadRepository();
  bool _loading = false;

  Future<void> _open() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final bytes = await _repo.documentBytesFromUrl(widget.url.trim());
      final dir = await Directory.systemTemp.createTemp('ocr_doc');
      final f = File('${dir.path}/document.pdf');
      await f.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => LeadDocPdfViewer(path: f.path),
      ));
    } catch (e) {
      if (mounted) {
        AppToast.show(
            context, e.toString().replaceFirst('ApiException: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _loading ? null : _open,
      icon: _loading
          ? const SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.purple))
          : const Icon(Icons.picture_as_pdf_outlined, size: 16),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.purple,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: const BorderSide(color: AppColors.purple),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      label: const Text('View Document',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
    );
  }
}

/// Post Disbursement section — the NACH mandate details (when the API sends
/// them) + post-disbursement documents (e.g. RC Book), tappable to view.
class PostDisbursementSection extends StatelessWidget {
  const PostDisbursementSection({super.key, required this.data});
  final PostDisbursement data;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final mandateRows =
        data.mandate == null ? const <(String, String)>[] : _scalarRows(data.mandate!);
    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 6, top: 4),
          child: Text(text,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: p.title)),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (mandateRows.isNotEmpty) ...[
          label('Mandate'),
          for (final (l, v) in mandateRows) DetailRow(label: l, value: v),
        ],
        if (data.documents.isNotEmpty) ...[
          if (mandateRows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1, color: p.fieldBorder),
            ),
          label('Documents'),
          const SizedBox(height: 6),
          DocThumbGrid(
            children: [for (final doc in data.documents) LeadDocTile(doc: doc)],
          ),
        ],
        if (mandateRows.isEmpty && data.documents.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No post-disbursement data',
                style: TextStyle(fontSize: 13.5, color: p.subtitle)),
          ),
      ],
    );
  }
}

// OCR documentCode → friendly title. Falls back to a prettified code.
String _ocrDocLabel(String code) {
  switch (code.toUpperCase()) {
    case 'AADHAAR':
      return 'Aadhaar';
    case 'CO_AADHAAR':
      return 'Co-Applicant Aadhaar';
    case 'PAN':
      return 'PAN';
    case 'CO_PAN':
      return 'Co-Applicant PAN';
    case 'ADDRESS_PROOF':
      return 'Address Proof';
    case 'CO_ADDRESS_PROOF':
      return 'Co-Applicant Address Proof';
    case 'PASSBOOK':
      return 'Bank Passbook';
    case 'RTO_KIT':
      return 'RTO Kit';
    case 'INVOICE':
      return 'Invoice';
    case 'PDC1':
      return 'Security Cheque 1';
    case 'PDC2':
      return 'Security Cheque 2';
    case 'INSURANCE':
      return 'Insurance';
    case 'HYPOTHECATION_DOC':
      return 'Hypothecation Document';
    case 'MMR':
      return 'MMR';
    default:
      return _pretty(code);
  }
}

// Keys inside extractedData that are internal flags — not shown as rows.
const Set<String> _skipOcrKeys = {
  'ocrStatus', 'verificationStatus', 'verificationMethod',
};

// Flatten an extractedData map to (label, value) rows — only scalar
// (string/number) fields, skipping nulls, nested objects/arrays and flags.
List<(String, String)> _scalarRows(Map<String, dynamic> data) {
  final out = <(String, String)>[];
  data.forEach((k, v) {
    if (_skipOcrKeys.contains(k)) return;
    if (v == null || v is Map || v is List || v is bool) return;
    final val = v.toString().trim();
    if (val.isEmpty) return;
    out.add(('${_pretty(k)}:', val));
  });
  return out;
}

// "aadhaarNumber"/"full_address"/"OCRStatus" → "Aadhaar Number" / "Full Address".
String _pretty(String key) {
  final spaced = key
      .replaceAll('_', ' ')
      .replaceAllMapped(
          RegExp(r'(?<=[a-z0-9])(?=[A-Z])'), (m) => ' ')
      .replaceAllMapped(
          RegExp(r'(?<=[A-Z])(?=[A-Z][a-z])'), (m) => ' ');
  return spaced
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

// ---- Display formatters (presentation only — the transmitted value unchanged) ----

// "373003.00" → "₹ 3,73,003"; "5005.63" → "₹ 5,005.63". Non-numeric stays as-is.
String _money(String raw) {
  final v = raw.trim();
  if (v.isEmpty) return '';
  final n = double.tryParse(v);
  if (n == null) return v;
  final isWhole = n == n.roundToDouble();
  final fixed = isWhole ? n.toStringAsFixed(0) : n.toStringAsFixed(2);
  final neg = fixed.startsWith('-');
  final body = neg ? fixed.substring(1) : fixed;
  final dot = body.indexOf('.');
  final intPart = dot >= 0 ? body.substring(0, dot) : body;
  final decPart = dot >= 0 ? body.substring(dot) : '';
  return '${neg ? '-' : ''}₹ ${_indianGroup(intPart)}$decPart';
}

// "20.00" → "20%"; "24.00" → "24%". Non-numeric stays as-is.
String _percent(String raw) {
  final v = raw.trim();
  if (v.isEmpty) return '';
  final n = double.tryParse(v);
  if (n == null) return v;
  final isWhole = n == n.roundToDouble();
  return '${isWhole ? n.toStringAsFixed(0) : n.toStringAsFixed(2)}%';
}

// 60 → "60 months".
String _tenure(String raw) {
  final v = raw.trim();
  if (v.isEmpty) return '';
  return '$v months';
}

// Indian digit grouping for an integer string (e.g. "373003" → "3,73,003").
String _indianGroup(String digits) {
  if (digits.length <= 3) return digits;
  final last3 = digits.substring(digits.length - 3);
  var rest = digits.substring(0, digits.length - 3);
  final groups = <String>[];
  while (rest.length > 2) {
    groups.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) groups.insert(0, rest);
  return '${groups.join(',')},$last3';
}

// "positive" → "Positive"; "self_owned" → "Self Owned". Blank stays blank.
String _cap(String s) {
  final t = s.replaceAll('_', ' ').trim();
  if (t.isEmpty) return '';
  return t
      .split(RegExp(r'\s+'))
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
      .join(' ');
}
