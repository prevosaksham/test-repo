import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import '../../core/constants/app_assets.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/models/person_detail.dart';
import '../../data/models/uploaded_doc.dart';
import '../widgets/doc_thumb.dart';
import '../../core/utils/date_format.dart';
import '../../data/repositories/application_repository.dart';
import '../../theme/app_colors.dart';
import '../application/application_flow_ui.dart';

/// Application Details tab — Applicant / Co-Applicant captured details and their
/// uploaded documents, from `data.applicationDetails`. Everything is read-only
/// and only the fields the API actually returns are shown.
class ViewLeadDetailsTab extends StatefulWidget {
  const ViewLeadDetailsTab({
    super.key,
    required this.applicant,
    required this.coApplicant,
    required this.applicantDocs,
    required this.coApplicantDocs,
    this.bankDetails,
    this.sectionTitle = 'Application & KYC',
    required this.expanded,
    required this.onToggle,
  });

  final PersonDetail? applicant;
  final PersonDetail? coApplicant;
  final List<UploadedDoc> applicantDocs;
  final List<UploadedDoc> coApplicantDocs;
  // Applicant's bank details — only shown under the Applicant sub-tab.
  final BankDetails? bankDetails;
  // Accordion header title from the API (`applicationAndKyc.title`).
  final String sectionTitle;
  // Controlled by the parent so only ONE section is open at a time.
  final bool expanded;
  final VoidCallback onToggle;

  @override
  State<ViewLeadDetailsTab> createState() => _ViewLeadDetailsTabState();
}

class _ViewLeadDetailsTabState extends State<ViewLeadDetailsTab> {
  int _sub = 0; // 0 = Applicant, 1 = Co-Applicant

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
          _sectionHeader(),
          if (widget.expanded) ...[
            Divider(height: 1, color: p.fieldBorder),
            Padding(
              padding: const EdgeInsets.all(14),
              child: _content(),
            ),
          ],
        ],
      ),
    );
  }

  // Expandable section header — the API's `applicationAndKyc.title` with a
  // chevron (e.g. "Application & KYC").
  Widget _sectionHeader() {
    final p = context.palette;
    return GestureDetector(
      onTap: widget.onToggle,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
        child: Row(
          children: [
            Expanded(
              child: Text(widget.sectionTitle,
                  style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: p.title)),
            ),
            Icon(
                widget.expanded
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                size: 24,
                color: p.subtitle),
          ],
        ),
      ),
    );
  }

  // Section body — Applicant / Co-Applicant captured details + their docs.
  Widget _content() {
    final p = context.palette;
    final isApplicant = _sub == 0;
    final person = isApplicant ? widget.applicant : widget.coApplicant;
    final docs = isApplicant ? widget.applicantDocs : widget.coApplicantDocs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _subTabs(),
        const SizedBox(height: 14),
        _SubHeading(isApplicant ? 'Applicant Details' : 'Co-Applicant Details'),
        if (person == null)
          _empty('No ${isApplicant ? 'applicant' : 'co-applicant'} details')
        else if (isApplicant)
          ..._applicantRows(person)
        else
          ..._coApplicantRows(person),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Divider(height: 1, color: p.fieldBorder),
        ),
        const _SubHeading('Uploaded Documents'),
        const SizedBox(height: 6),
        if (docs.isEmpty)
          _empty('No documents uploaded')
        else
          DocThumbGrid(
            children: [for (final d in docs) LeadDocTile(doc: d)],
          ),
        // Bank details belong to the applicant, so only show them there.
        if (isApplicant) ..._bankSection(widget.bankDetails),
      ],
    );
  }

  // Bank Details block, shown only when the API returned at least one field.
  List<Widget> _bankSection(BankDetails? b) {
    final p = context.palette;
    final rows = b == null
        ? const <Widget>[]
        : _personRows([
            ('Account Holder Name:', b.accountHolderName, null),
            ('Bank Name:', b.bankName, null),
            ('Branch Name:', b.branchName, null),
            ('Account Number:', b.accountNumber, null),
            ('IFSC Code:', b.ifscCode, null),
            ('Account Type:', _cap(b.accountType), null),
          ]);
    return [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Divider(height: 1, color: p.fieldBorder),
      ),
      const _SubHeading('Bank Details'),
      if (rows.isEmpty) _empty('No bank details') else ...rows,
    ];
  }

  Widget _empty(String text) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(text, style: TextStyle(fontSize: 13.5, color: p.subtitle)),
    );
  }

  Widget _subTabs() {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: p.fieldBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.fieldBorder),
      ),
      child: Row(
        children: [
          _subTabBtn('Applicant Details', 0),
          _subTabBtn('Co-Applicant Details', 1),
        ],
      ),
    );
  }

  Widget _subTabBtn(String label, int index) {
    final p = context.palette;
    final selected = _sub == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _sub = index),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? AppColors.purple : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : p.subtitle)),
        ),
      ),
    );
  }

  // Rows are built only when the source value is present (blank → row hidden),
  // so we never render an empty "Label : —".
  List<Widget> _personRows(List<(String, String, String?)> entries) {
    final rows = <Widget>[];
    for (final (label, value, sub) in entries) {
      if (value.trim().isEmpty) continue;
      rows.add(DetailRow(label: label, sublabel: sub, value: value));
    }
    return rows;
  }

  List<Widget> _applicantRows(PersonDetail a) => _personRows([
        ('Full Name:', a.fullName, '(as per PAN)'),
        ("Father's Name:", a.fatherName, null),
        ('Mobile Number:', a.phoneNumber, null),
        ('DOB:', formatDob(a.dob), null),
        ('Gender:', _cap(a.gender), null),
        ('Age:', a.ageLabel, null),
        (a.idNumberLabel, a.idNumber, null),
        ('PAN:', a.panNumber, null),
        ('Driving License:', a.dlNumber, null),
        ('DL Expiry Date:', a.dlValidityDate, null),
        ('DL Issue Date:', a.dlIssueDate, null),
        ('DL Issuing RTO:', a.dlIssueRTO, null),
        ('Marital Status:', _cap(a.maritalStatus), null),
        ('Address:', a.address, '(as per Aadhar)'),
        ('Permanent Address:', a.permanentAddressDisplay, null),
        (
          'Is the current address same as the Aadhar address?',
          a.sameAsPermanent ? 'Yes' : 'No',
          null
        ),
        ('Current Address:', a.currentAddressDisplay, null),
        ('Residence Type:', _cap(a.residenceType), null),
        ('Owner Name:', a.ownerName, null),
        ('Consumer Name:', a.consumerName, null),
        ('Bill / Reference Number:', a.billNumber, null),
      ]);

  List<Widget> _coApplicantRows(PersonDetail c) => _personRows([
        ('Full Name:', c.fullName, '(as per PAN)'),
        ("Father's Name:", c.fatherName, null),
        ('Mobile Number:', c.phoneNumber, null),
        ('DOB:', formatDob(c.dob), null),
        ('Gender:', _cap(c.gender), null),
        ('Age:', c.ageLabel, null),
        (c.idNumberLabel, c.idNumber, null),
        ('PAN:', c.panNumber, null),
        ('Relation with Applicant:', _cap(c.relationship), null),
        ('Address:', c.address, '(as per Aadhar)'),
        ('Permanent Address:', c.permanentAddressDisplay, null),
        (
          'Is the current address same as the Aadhar address?',
          c.sameAsPermanent ? 'Yes' : 'No',
          null
        ),
        ('Current Address:', c.currentAddressDisplay, null),
        ('Residence Type:', _cap(c.residenceType), null),
        ('Owner Name:', c.ownerName, null),
        ('Consumer Name:', c.consumerName, null),
        ('Bill / Reference Number:', c.billNumber, null),
      ]);
}

/// Capitalise the API's lowercase enums ("female" → "Female", "self_owned" →
/// "Self Owned"). Blank stays blank.
String _cap(String s) {
  final t = s.replaceAll('_', ' ').trim();
  if (t.isEmpty) return '';
  return t
      .split(RegExp(r'\s+'))
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

/// Friendly (label, sublabel) for a document code.
(String, String?) _docLabel(String code) {
  switch (code.toUpperCase()) {
    case 'AADHAAR_FRONT':
    case 'CO_AADHAAR_FRONT':
      return ('Aadhaar', '(Front)');
    case 'AADHAAR_BACK':
    case 'CO_AADHAAR_BACK':
      return ('Aadhaar', '(Back)');
    case 'PAN':
    case 'CO_PAN':
      return ('PAN', null);
    case 'APPLICANT_PIC':
    case 'APPLICANT_IMAGE':
      return ('Applicant Photo', null);
    case 'CO_APPLICANT_PIC':
    case 'CO_APPLICANT_IMAGE':
      return ('Co-Applicant Photo', null);
    case 'PASSBOOK':
      return ('Bank Passbook', null);
    case 'DRIVING_LICENCE':
      return ('Driving License', null);
    case 'ADDRESS_PROOF':
    case 'CO_ADDRESS_PROOF':
      return ('Address Proof', null);
    case 'CURRENT_ADDRESS_PROOF':
    case 'CO_CURRENT_ADDRESS_PROOF':
      return ('Current Address Proof', null);
    case 'VOTER_ID':
    case 'CO_VOTER_ID':
      return ('Voter ID', null);
    default:
      return (_cap(code), null);
  }
}

/// A document thumbnail (small base64 preview, or a file icon) tappable to open
/// a full-screen preview. The list (from `/rm/lead-details`) only carries a
/// thumbnail now, so the FULL file is fetched on tap via POST
/// /application/document (documentId + applicantType).
class LeadDocTile extends StatefulWidget {
  const LeadDocTile({super.key, required this.doc});
  final UploadedDoc doc;

  @override
  State<LeadDocTile> createState() => LeadDocTileState();
}

class LeadDocTileState extends State<LeadDocTile> {
  final ApplicationRepository _repo = ApplicationRepository();
  bool _loading = false; // fetching the full file to view

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final doc = widget.doc;
    final (label, sub) = _docLabel(doc.documentCode);
    final Uint8List? thumb = doc.isPdf ? null : doc.thumbnailBytes;
    final canView = doc.id.isNotEmpty;

    return GestureDetector(
      onTap: (!canView || _loading) ? null : _openDoc,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: p.fieldBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.fieldBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: double.infinity,
                  color: AppColors.purple.withValues(alpha: 0.06),
                  alignment: Alignment.center,
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.4, color: AppColors.purple),
                        )
                      : DocThumbImage(
                          url: doc.isPdf ? '' : doc.thumbnailUrl,
                          bytes: thumb,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          placeholder: Icon(
                              doc.isPdf
                                  ? Icons.picture_as_pdf_outlined
                                  : Icons.image_outlined,
                              size: 28,
                              color: p.iconGrey)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                AppIcon(AppAssets.document, size: 18, color: AppColors.purple),
                const SizedBox(width: 6),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text: label,
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: p.title)),
                      if (sub != null)
                        TextSpan(
                            text: ' $sub',
                            style: TextStyle(fontSize: 11.5, color: p.subtitle)),
                    ]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Fetch the full file on demand, then show it (image dialog / PDF viewer).
  Future<void> _openDoc() async {
    final doc = widget.doc;
    final type = doc.documentCode.trim().toUpperCase().startsWith('CO_')
        ? 'CO_APPLICANT'
        : 'APPLICANT';
    setState(() => _loading = true);
    try {
      final file =
          await _repo.getDocumentFile(documentId: doc.id, applicantType: type);
      if (!mounted) return;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        AppToast.show(context, 'Preview not available for this document');
        return;
      }
      if (file.isPdf) {
        await _openPdf(bytes);
      } else {
        final (label, _) = _docLabel(doc.documentCode);
        _preview(context, bytes, label);
      }
    } on ApiException catch (e) {
      if (mounted) AppToast.show(context, e.message);
    } catch (_) {
      if (mounted) AppToast.show(context, 'Could not load this document');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Write the fetched PDF bytes to a temp file and open the full-screen viewer.
  Future<void> _openPdf(Uint8List bytes) async {
    try {
      final name =
          widget.doc.fileName.isNotEmpty ? widget.doc.fileName : 'document.pdf';
      final f = File('${Directory.systemTemp.path}/$name');
      await f.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => LeadDocPdfViewer(path: f.path),
      ));
    } catch (_) {
      if (mounted) AppToast.show(context, 'Could not open this PDF');
    }
  }

  void _preview(BuildContext context, Uint8List bytes, String label) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                maxScale: 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// Full-screen viewer for a fetched PDF document (View Lead → Details).
class LeadDocPdfViewer extends StatefulWidget {
  const LeadDocPdfViewer({super.key, required this.path});
  final String path;

  @override
  State<LeadDocPdfViewer> createState() => LeadDocPdfViewerState();
}

class LeadDocPdfViewerState extends State<LeadDocPdfViewer> {
  bool _error = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Document', style: TextStyle(fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: _error
          ? const Center(
              child: Text('Could not open this PDF',
                  style: TextStyle(color: Colors.white70)),
            )
          : PDFView(
              filePath: widget.path,
              swipeHorizontal: false,
              onError: (_) {
                if (mounted) setState(() => _error = true);
              },
            ),
    );
  }
}

/// Small bold sub-heading inside the card.
class _SubHeading extends StatelessWidget {
  const _SubHeading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Text(text,
          style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w700, color: p.title)),
    );
  }
}
