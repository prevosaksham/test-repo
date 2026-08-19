import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import '../../core/constants/app_assets.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/date_format.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/models/lead_item.dart';
import '../../data/models/person_detail.dart';
import '../../data/models/uploaded_doc.dart';
import '../../data/repositories/application_repository.dart';
import '../../theme/app_colors.dart';
import '../widgets/doc_thumb.dart';
import 'application_flow_ui.dart';

/// Read-only "View Application" — the submitted Application Details
/// (Applicant / Co-Applicant tabs) + Bank Details + uploaded documents, all
/// from `POST /application/details`. Opened from the Submit Application screen.
class ViewApplicationScreen extends StatefulWidget {
  const ViewApplicationScreen({super.key, required this.lead});
  final LeadItem lead;

  @override
  State<ViewApplicationScreen> createState() => _ViewApplicationScreenState();
}

class _ViewApplicationScreenState extends State<ViewApplicationScreen> {
  final ApplicationRepository _repo = ApplicationRepository();
  int _tab = 0; // 0 = Applicant, 1 = Co-Applicant
  bool _loading = true;
  String? _error;
  ApplicationDetails? _details;

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
      final d = await _repo.getApplicationDetails(leadId: widget.lead.id);
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

  String _cap(String s) {
    final t = s.trim();
    if (t.isEmpty) return '';
    return '${t[0].toUpperCase()}${t.substring(1)}';
  }

  // Tap a document → fetch the FULL file on demand (POST /application/document,
  // documentId + applicantType — the list only carries a thumbnail now), then
  // show it full-screen (image zoom / PDF viewer).
  Future<void> _openDoc(UploadedDoc doc) async {
    if (doc.id.isEmpty) {
      AppToast.show(context, 'Preview not available for this document');
      return;
    }
    final type = doc.documentCode.trim().toUpperCase().startsWith('CO_')
        ? 'CO_APPLICANT'
        : 'APPLICANT';
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: AppColors.purple)),
    );
    DocumentFile? file;
    try {
      file = await _repo.getDocumentFile(documentId: doc.id, applicantType: type);
    } on ApiException catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        AppToast.show(context, e.message);
      }
      return;
    } catch (_) {
      if (mounted) {
        Navigator.of(context).pop();
        AppToast.show(context, 'Could not load this document');
      }
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(); // close loader
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      AppToast.show(context, 'Preview not available for this document');
      return;
    }
    if (file.isPdf) {
      try {
        final name = file.fileName.isNotEmpty ? file.fileName : 'document.pdf';
        final f = File('${Directory.systemTemp.path}/$name');
        await f.writeAsBytes(bytes, flush: true);
        if (!mounted) return;
        Navigator.of(context).push(MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => _DocPdfViewer(path: f.path),
        ));
      } catch (_) {
        if (mounted) AppToast.show(context, 'Could not open this PDF');
      }
    } else {
      _previewImage(bytes);
    }
  }

  void _previewImage(Uint8List bytes) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: InteractiveViewer(
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(6),
              child: GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: Colors.black54),
                  child: const Icon(Icons.close, size: 20, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppFlowScaffold(
      title: 'Application Details',
      body: _body(),
    );
  }

  Widget _body() {
    final p = context.palette;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 40, color: p.subtitle),
              const SizedBox(height: 12),
              Text(_error!,
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      children: [
        _tabs(),
        const SizedBox(height: 14),
        if (_tab == 0) ..._applicant() else ..._coApplicant(),
      ],
    );
  }

  // ---- Segmented tabs ----
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
          _tabBtn('Applicant Details', 0),
          _tabBtn('Co-Applicant Details', 1),
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
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : p.subtitle,
            ),
          ),
        ),
      ),
    );
  }

  // ---- Applicant tab ----
  List<Widget> _applicant() {
    final a = _details?.applicant;
    final bank = _details?.bankDetails;
    return [
      FlowCard(
        heading: 'Applicant Details',
        child: Column(
          children: [
            DetailRow(
                label: 'Full Name:',
                sublabel: '(as per PAN)',
                value: a?.fullName ?? ''),
            DetailRow(label: 'Mobile Number:', value: a?.phoneNumber ?? ''),
            DetailRow(label: 'DOB:', value: formatDob(a?.dob)),
            DetailRow(label: 'Gender:', value: _cap(a?.gender ?? '')),
            DetailRow(label: 'Age:', value: a?.ageLabel ?? ''),
            DetailRow(
                label: a?.idNumberLabel ?? 'Aadhar Number:',
                value: a?.idNumber ?? ''),
            DetailRow(label: 'PAN:', value: a?.panNumber ?? ''),
            DetailRow(label: 'Driving License:', value: a?.dlNumber ?? ''),
            DetailRow(label: 'DL Expiry Date:', value: a?.dlValidityDate ?? ''),
            DetailRow(label: 'DL issuing RTO:', value: a?.dlIssueRTO ?? ''),
            DetailRow(label: 'Marital Status:', value: _cap(a?.maritalStatus ?? '')),
            DetailRow(
                label: 'Address:',
                sublabel: '(as per ${a?.idTypeLabel ?? 'Aadhar'})',
                value: a?.address ?? ''),
            DetailRow(
                label: 'Permanent Address:',
                value: a?.permanentAddressDisplay ?? ''),
            DetailRow(
                label: 'Is the current address same as the Aadhar address?',
                value: (a?.sameAsPermanent ?? false) ? 'Yes' : 'No'),
            DetailRow(
                label: 'Current Address:', value: a?.currentAddressDisplay ?? ''),
            DetailRow(label: 'Residence Type:', value: a?.residenceType ?? ''),
            DetailRow(label: 'Owner Name:', value: a?.consumerName ?? ''),
            DetailRow(
                label: 'Bill / Reference Number:', value: a?.billNumber ?? ''),
          ],
        ),
      ),
      const SizedBox(height: 14),
      FlowCard(
        heading: 'Bank Details',
        child: Column(
          children: [
            DetailRow(
                label: 'A/c Holder Name:',
                value: bank?.accountHolderName ?? ''),
            DetailRow(label: 'Bank Name:', value: bank?.bankName ?? ''),
            DetailRow(label: 'Branch Name:', value: bank?.branchName ?? ''),
            DetailRow(label: 'IFSC Code:', value: bank?.ifscCode ?? ''),
            DetailRow(label: 'Account Type:', value: bank?.accountType ?? ''),
            DetailRow(
                label: 'Account Number:', value: bank?.accountNumber ?? ''),
          ],
        ),
      ),
      const SizedBox(height: 14),
      _uploadedDocs(_details?.applicantDocs ?? const []),
    ];
  }

  // ---- Co-Applicant tab ----
  List<Widget> _coApplicant() {
    final c = _details?.coApplicant;
    return [
      FlowCard(
        heading: 'Co-Applicant Details',
        child: Column(
          children: [
            DetailRow(
                label: 'Full Name:',
                sublabel: '(as per PAN)',
                value: c?.fullName ?? ''),
            DetailRow(label: 'Mobile Number:', value: c?.phoneNumber ?? ''),
            DetailRow(label: 'DOB:', value: formatDob(c?.dob)),
            DetailRow(label: 'Gender:', value: _cap(c?.gender ?? '')),
            DetailRow(label: 'Age:', value: c?.ageLabel ?? ''),
            DetailRow(
                label: c?.idNumberLabel ?? 'Aadhar Number:',
                value: c?.idNumber ?? ''),
            DetailRow(label: 'PAN:', value: c?.panNumber ?? ''),
            DetailRow(
                label: 'Relation with Applicant:',
                value: _cap(c?.relationship ?? '')),
            DetailRow(
                label: 'Address:',
                sublabel: '(as per ${c?.idTypeLabel ?? 'Aadhar'})',
                value: c?.address ?? ''),
            DetailRow(
                label: 'Permanent Address:',
                value: c?.permanentAddressDisplay ?? ''),
            DetailRow(
                label: 'Is the current address same as the Aadhar address?',
                value: (c?.sameAsPermanent ?? false) ? 'Yes' : 'No'),
            DetailRow(
                label: 'Current Address:', value: c?.currentAddressDisplay ?? ''),
            DetailRow(label: 'Residence Type:', value: c?.residenceType ?? ''),
            DetailRow(label: 'Owner Name:', value: c?.consumerName ?? ''),
            DetailRow(
                label: 'Bill / Reference Number:', value: c?.billNumber ?? ''),
          ],
        ),
      ),
      const SizedBox(height: 14),
      _uploadedDocs(_details?.coApplicantDocs ?? const []),
    ];
  }

  Widget _uploadedDocs(List<UploadedDoc> docs) {
    final p = context.palette;
    return FlowCard(
      heading: 'Uploaded Documents',
      child: docs.isEmpty
          ? Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('No documents uploaded.',
                  style: TextStyle(fontSize: 13.5, color: p.subtitle)),
            )
          : GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: docs.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.95,
              ),
              itemBuilder: (_, i) => _DocTile(
                doc: docs[i],
                label: _docLabel(docs[i].documentCode),
                onTap: () => _openDoc(docs[i]),
              ),
            ),
    );
  }

  // Readable document name from its code.
  String _docLabel(String code) {
    final c = code.trim().toUpperCase().replaceFirst('CO_', '');
    switch (c) {
      case 'AADHAAR_FRONT':
        return 'Aadhaar (Front)';
      case 'AADHAAR_BACK':
        return 'Aadhaar (Back)';
      case 'AADHAAR':
        return 'Aadhaar';
      case 'PAN':
        return 'PAN';
      case 'DRIVING_LICENCE':
      case 'DRIVING_LICENSE':
        return 'Driving License';
      case 'PASSBOOK':
        return 'Bank Passbook';
      case 'APPLICANT_IMAGE':
      case 'APPLICANT_PIC':
      case 'PHOTO':
        return 'Photo';
      case 'CO_APPLICANT_IMAGE':
      case 'CO_APPLICANT_PIC':
        return 'Co-Applicant Photo';
      case 'ADDRESS_PROOF':
        return 'Address Proof';
      case 'CURRENT_ADDRESS_PROOF':
        return 'Current Address Proof';
      case 'PERMANENT_ADDRESS_PROOF':
        return 'Permanent Address Proof';
      default:
        return c
            .split('_')
            .where((w) => w.isNotEmpty)
            .map((w) => '${w[0]}${w.substring(1).toLowerCase()}')
            .join(' ');
    }
  }
}

class _DocTile extends StatelessWidget {
  const _DocTile({required this.doc, required this.label, this.onTap});
  final UploadedDoc doc;
  final String label;
  final VoidCallback? onTap; // tap → preview

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bytes = doc.isPdf ? null : doc.thumbnailBytes; // small list thumbnail
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
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
            child: Stack(
              children: [
                Container(
                  width: double.infinity,
                  height: double.infinity,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: AppColors.purple.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DocThumbImage(
                      url: doc.isPdf ? '' : doc.thumbnailUrl,
                      bytes: bytes,
                      fit: BoxFit.cover,
                      placeholder: Icon(
                          doc.isPdf
                              ? Icons.picture_as_pdf
                              : Icons.image_outlined,
                          size: 30,
                          color: doc.isPdf ? AppColors.statusRed : p.iconGrey)),
                ),
                // Tap-to-view hint.
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                        shape: BoxShape.circle, color: Colors.black45),
                    child: const Icon(Icons.visibility,
                        size: 14, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              AppIcon(AppAssets.document, size: 18, color: AppColors.purple),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: p.title),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.check_circle, size: 18, color: AppColors.success),
            ],
          ),
        ],
      ),
      ),
    );
  }
}

/// Full-screen viewer for a previewed PDF document.
class _DocPdfViewer extends StatefulWidget {
  const _DocPdfViewer({required this.path});
  final String path;

  @override
  State<_DocPdfViewer> createState() => _DocPdfViewerState();
}

class _DocPdfViewerState extends State<_DocPdfViewer> {
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
