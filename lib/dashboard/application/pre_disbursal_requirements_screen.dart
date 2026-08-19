import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/constants/app_assets.dart';
import '../../core/widgets/app_icon.dart';
import '../../data/models/financial_approval.dart';
import '../../data/models/lead_item.dart';
import '../../data/repositories/application_repository.dart';
import '../../data/repositories/lead_repository.dart';
import '../../theme/app_colors.dart';
import '../widgets/doc_thumb.dart';
import '../widgets/interaction_ui.dart';
import 'application_flow_ui.dart';
import 'disbursement_status_screen.dart';

/// Pre-Disbursal Requirements — applicant header, the pre-disbursal documents
/// (upload / remove via the shared `/application/upload` + delete-document
/// APIs), and asset details. Data from `POST /field-verification/details`.
class PreDisbursalRequirementsScreen extends StatefulWidget {
  const PreDisbursalRequirementsScreen({super.key, required this.lead});
  final LeadItem lead;

  @override
  State<PreDisbursalRequirementsScreen> createState() =>
      _PreDisbursalRequirementsScreenState();
}

// (docCode, label) — docCode is the field sent to /application/upload.
// ALL of these are mandatory: each row shows a red `*` and Submit stays
// disabled until every one of them is uploaded.
const _kDocs = <(String, String)>[
  ('RTO_KIT', 'RTO Kit Forms'),
  ('INVOICE', 'Invoice'),
  ('PDC1', 'Security Cheque 1'), // server code PDC1 (pre-fill from vehicleDocuments.pdc1)
  ('PDC2', 'Security Cheque 2'), // server code PDC2 (pre-fill from vehicleDocuments.pdc2)
  ('INSURANCE', 'Insurance'),
  ('HYPOTHECATION_DOC', 'Hypothecation Document'),
  ('MMR', 'MMR Details'),
];

class _PreDisbursalRequirementsScreenState
    extends State<PreDisbursalRequirementsScreen> {
  final _leadRepo = LeadRepository();
  final _appRepo = ApplicationRepository();

  bool _loading = true;
  String? _error;
  ApplicantDetails? _applicant;
  String? _loanId; // loanDetails.loanId — shown in the header
  AssetDetails? _asset;
  Stage? _stage; // current (Predisbursal) stage → stageId on submit
  bool _submitting = false;

  final Set<String> _uploaded = {}; // doc codes already on the server
  final Set<String> _busy = {}; // doc codes currently uploading/removing
  final Map<String, String> _docId = {}; // vehicle doc code -> documentId
  final Map<String, Uint8List> _thumb = {}; // vehicle doc code -> thumbnail bytes
  final Map<String, String> _thumbUrl = {}; // vehicle doc code -> thumbnail url
  final Set<String> _viewing = {}; // codes whose full file is being fetched

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
      final data = await _leadRepo.getFinancialApproval(leadId: widget.lead.id);
      if (!mounted) return;
      debugPrint('[PreDisbursal] assetDetails=${data.assetDetails != null} '
          'chassisStatus="${data.assetDetails?.chassisStatus}"');
      setState(() {
        _applicant = data.applicant;
        _loanId = data.loan.loanId;
        _asset = data.assetDetails;
        _stage = data.stageByKey('PREDISBURSAL_UPLOADS') ?? data.currentStage;
        _applyVehicleDocs(data.vehicleDocuments);
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

  // Sync uploaded state + documentId + thumbnail from the response, matched by
  // documentCode (so any doc the server returns in vehicleDocuments — pdc1,
  // mmr, hypothecation, … — gets its thumbnail, no hardcoded key map needed).
  void _applyVehicleDocs(Map<String, VehicleDoc> vd) {
    for (final doc in vd.values) {
      final code = doc.documentCode.trim();
      if (code.isEmpty) continue;
      _uploaded.add(code);
      _docId[code] = doc.id;
      final t = doc.thumbnailBytes;
      if (t != null) _thumb[code] = t;
      final u = doc.thumbnailUrl;
      if (u.isNotEmpty) _thumbUrl[code] = u;
    }
  }

  // Silently re-fetch the details after an upload and update: (1) the Asset
  // Details — an uploaded doc (e.g. chassis/engine) can populate these via OCR,
  // so they refresh in place as each doc is added; and (2) the given doc's
  // thumbnail + documentId (matched by documentCode). No full-screen loader.
  Future<void> _refreshDoc(String code) async {
    try {
      final data = await _leadRepo.getFinancialApproval(leadId: widget.lead.id);
      if (!mounted) return;
      // Find this doc's fresh thumbnail/id (may be null if server has none yet).
      VehicleDoc? match;
      for (final doc in data.vehicleDocuments.values) {
        if (doc.documentCode.trim() == code) {
          match = doc;
          break;
        }
      }
      setState(() {
        // Always refresh Asset Details from the latest response.
        _asset = data.assetDetails;
        if (match != null) {
          _docId[code] = match.id;
          final t = match.thumbnailBytes;
          if (t != null) _thumb[code] = t;
          final u = match.thumbnailUrl;
          if (u.isNotEmpty) _thumbUrl[code] = u;
        }
      });
    } catch (_) {/* best-effort */}
  }

  // Every document in [_kDocs] is mandatory — Submit enables ONLY when all of
  // them are on the server and nothing is mid-upload/mid-remove.
  bool get _allDocsUploaded =>
      _kDocs.every((d) => _uploaded.contains(d.$1));
  bool get _canSubmit => !_submitting && _busy.isEmpty && _allDocsUploaded;

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: error ? AppColors.statusRed : AppColors.success,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // Submit → POST /pre-disbursal/submit with only { applicationId, stageId }.
  Future<void> _submit() async {
    if (_submitting) return;
    if (!_allDocsUploaded) {
      _snack('Please upload all the required documents.', error: true);
      return;
    }
    final appId = _applicant?.id ?? '';
    final stageId = _stage?.stageId ?? '';
    if (appId.isEmpty || stageId.isEmpty) {
      _snack('Application / stage details not available.', error: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      final res = await _appRepo.preDisbursalSubmit(
        applicationId: int.tryParse(appId) ?? appId,
        stageId: int.tryParse(stageId) ?? stageId,
      );
      if (!mounted) return;
      final ok =
          res is Map && (res['success'] == true || res['status'] == true);
      final msg = (res is Map &&
              res['message'] is String &&
              (res['message'] as String).trim().isNotEmpty)
          ? (res['message'] as String).trim()
          : (ok ? 'Submitted successfully' : 'Could not submit');
      if (!ok) {
        _snack(msg, error: true);
        return;
      }
      _snack(msg);
      // Submitted → application forwarded for disbursement. Go to the
      // Disbursement Status page (it loads /application/disbursement-status and
      // shows Pending/Success itself). Replace so Back doesn't return to the form.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => DisbursementStatusScreen(lead: widget.lead),
        ),
      );
    } catch (e) {
      _snack(e.toString().replaceFirst('ApiException: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // Tapping Upload opens a sheet (same as Upload Documents): pick a PDF/image
  // file OR capture from the camera.
  Future<void> _showUploadSheet(String code) async {
    if (_busy.contains(code)) return;
    final p = context.palette;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: p.cardBg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: p.fieldBorder,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.folder_open, color: AppColors.purple),
              title: Text('Choose File',
                  style:
                      TextStyle(color: p.title, fontWeight: FontWeight.w600)),
              subtitle: Text('Single PDF or image (png/jpg/jpeg)',
                  style: TextStyle(color: p.subtitle, fontSize: 12)),
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera, color: AppColors.purple),
              title: Text('Camera',
                  style:
                      TextStyle(color: p.title, fontWeight: FontWeight.w600)),
              subtitle: Text('Capture a document photo',
                  style: TextStyle(color: p.subtitle, fontSize: 12)),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == 'file') {
      await _pickFile(code);
    } else if (choice == 'camera') {
      await _capturePhoto(code);
    }
  }

  // Pick a single PDF/image file.
  Future<void> _pickFile(String code) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      allowMultiple: false,
    );
    final path = res?.files.single.path;
    if (path == null || !mounted) return;
    await _uploadPath(code, path);
  }

  // Capture from the camera, then crop (same cropper as Upload Documents).
  Future<void> _capturePhoto(String code) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.camera);
    if (picked == null || !mounted) return;
    final cropped = await _cropImage(picked.path);
    if (cropped == null || !mounted) return;
    await _uploadPath(code, cropped);
  }

  // Free/manual cropper — same config as the Upload Documents screen.
  Future<String?> _cropImage(String path) async {
    final cropped = await ImageCropper().cropImage(
      sourcePath: path,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 100,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Image',
          toolbarColor: AppColors.deepOrange,
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: AppColors.purple,
          lockAspectRatio: false,
          hideBottomControls: false,
          initAspectRatio: CropAspectRatioPreset.original,
          aspectRatioPresets: const [
            CropAspectRatioPreset.original,
            CropAspectRatioPreset.square,
            CropAspectRatioPreset.ratio3x2,
            CropAspectRatioPreset.ratio4x3,
            CropAspectRatioPreset.ratio16x9,
          ],
        ),
        IOSUiSettings(
          title: 'Crop Image',
          aspectRatioLockEnabled: false,
          resetAspectRatioEnabled: true,
          aspectRatioPickerButtonHidden: false,
          aspectRatioPresets: const [
            CropAspectRatioPreset.original,
            CropAspectRatioPreset.square,
            CropAspectRatioPreset.ratio3x2,
            CropAspectRatioPreset.ratio4x3,
            CropAspectRatioPreset.ratio16x9,
          ],
        ),
      ],
    );
    return cropped?.path;
  }

  // Upload the chosen file via the shared /application/upload API.
  Future<void> _uploadPath(String code, String path) async {
    setState(() => _busy.add(code));
    try {
      await _appRepo.uploadFiles(leadId: widget.lead.id, files: {code: path});
      if (!mounted) return;
      setState(() => _uploaded.add(code));
      // Load only this doc's fresh thumbnail (silent — no full page reload).
      await _refreshDoc(code);
      _snack('$code uploaded');
    } catch (e) {
      _snack(e.toString().replaceFirst('ApiException: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(code));
    }
  }

  // Remove an uploaded document via the shared delete-document API
  // (POST /application/delete-document { leadId, docCode }).
  Future<void> _remove(String code) async {
    if (_busy.contains(code)) return;
    setState(() => _busy.add(code));
    try { 
      final res =
          await _appRepo.deleteDocument(leadId: widget.lead.id, docCode: code);
      if (!mounted) return;
      // The delete API returns the raw envelope — verify it actually succeeded
      // (otherwise the refresh would just bring the document back).
      final ok =  
          res is Map && (res['success'] == true || res['status'] == true);
      if (!ok) {
        final msg = (res is Map &&
                res['message'] is String &&
                (res['message'] as String).trim().isNotEmpty)
            ? (res['message'] as String).trim()
            : 'Could not delete document';
        _snack(msg, error: true);
        return;
      }
      setState(() {
        _uploaded.remove(code);
        _docId.remove(code);
        _thumb.remove(code);
        _thumbUrl.remove(code);
      });
      _snack('$code removed');
    } catch (e) {
      _snack(e.toString().replaceFirst('ApiException: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(code));
    }
  }

  // Tap the thumbnail → fetch the full file (documentId) and view it in-app.
  Future<void> _view(String code) async {
    final id = _docId[code];
    if (id == null || id.isEmpty || _viewing.contains(code)) return;
    setState(() => _viewing.add(code));
    try {
      // View by documentId (documentCode/applicantType sent empty for now).
      final file = await _appRepo.getDocumentFile(
          documentId: id, applicantType: '', documentCode: '');
      if (!mounted) return;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        _snack('Document could not be loaded.', error: true);
        return;
      }
      if (file.isPdf) {
        final dir = await getTemporaryDirectory();
        final f = File('${dir.path}/${code}_view.pdf');
        await f.writeAsBytes(bytes, flush: true);
        if (!mounted) return;
        Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => _PdfViewer(path: f.path)));
      } else {
        _showImage(bytes);
      }
    } catch (e) {
      _snack(e.toString().replaceFirst('ApiException: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _viewing.remove(code));
    }
  }

  void _showImage(Uint8List bytes) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
                minScale: 0.8,
                maxScale: 4,
                child: Center(child: Image.memory(bytes))),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AppFlowScaffold(
        title: 'Pre- Disbursal Requirements',
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return AppFlowScaffold(
        title: 'Pre- Disbursal Requirements',
        body: _ErrorView(message: _error!, onRetry: _load),
      );
    }
    return AppFlowScaffold(
      title: 'Pre- Disbursal Requirements',
      bottomBar: InteractionBottomBar(
        actionLabel: 'Submit',
        // All documents are mandatory — Submit stays disabled until each one
        // has been uploaded.
        enabled: _canSubmit,
        onAction: _submit,
      ),
      body: Stack(
        children: [
          ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        children: [
          _HeaderCard(
              applicant: _applicant,
              loanId: _loanId,
              location: widget.lead.location),
          const SizedBox(height: 16),
          FlowCard(
            heading: 'Documents Upload',
            child: Column(
              children: [
                for (var i = 0; i < _kDocs.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _DocRow(
                    label: _kDocs[i].$2,
                    uploaded: _uploaded.contains(_kDocs[i].$1),
                    busy: _busy.contains(_kDocs[i].$1),
                    thumbnail: _thumb[_kDocs[i].$1],
                    thumbnailUrl: _thumbUrl[_kDocs[i].$1] ?? '',
                    viewing: _viewing.contains(_kDocs[i].$1),
                    onUpload: () => _showUploadSheet(_kDocs[i].$1),
                    onRemove: () => _remove(_kDocs[i].$1),
                    onView: () => _view(_kDocs[i].$1),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          _AssetDetailsCard(asset: _asset),
        ],
          ),
          if (_submitting)
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

/// Applicant header (Loan ID + name + phone + location).
class _HeaderCard extends StatelessWidget {
  const _HeaderCard(
      {required this.applicant, required this.loanId, required this.location});
  final ApplicantDetails? applicant;
  final String? loanId; // loanDetails.loanId
  final String location; // "City, State" from the lead

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    String v(String? s, String f) => (s != null && s.trim().isNotEmpty) ? s : f;
    return InteractionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Loan ID',
              style: TextStyle(fontSize: 12.5, color: p.subtitle)),
          const SizedBox(height: 3),
          Text(v(loanId, '—'),
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.purple)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: p.fieldBorder),
          ),
          Text(v(applicant?.applicantName, '—'),
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: p.title)),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.call, size: 16, color: p.subtitle),
              const SizedBox(width: 5),
              Text(v(applicant?.mobileNumber, '—'),
                  style: TextStyle(fontSize: 13.5, color: p.subtitle)),
              if (location.isNotEmpty) ...[
                const SizedBox(width: 14),
                Icon(Icons.location_on_outlined, size: 17, color: p.subtitle),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(location,
                      maxLines: 1,
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
}

/// One document row: thumbnail/icon + label + Upload button, or (once uploaded)
/// a thumbnail (tap → view) with a green tick + a remove (✕) — same UI style as
/// the Upload Documents page.
class _DocRow extends StatelessWidget {
  const _DocRow({
    required this.label,
    required this.uploaded,
    required this.busy,
    required this.viewing,
    required this.thumbnail,
    required this.thumbnailUrl,
    required this.onUpload,
    required this.onRemove,
    required this.onView,
  });
  final String label;
  final bool uploaded;
  final bool busy;
  final bool viewing;
  final Uint8List? thumbnail;
  final String thumbnailUrl;
  final VoidCallback onUpload;
  final VoidCallback onRemove;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // Left box: the uploaded thumbnail (tap → view) or a plain document icon.
    Widget leading;
    if (viewing) {
      leading = _box(
        p,
        const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.purple)),
      );
    } else if (uploaded && (thumbnail != null || thumbnailUrl.isNotEmpty)) {
      leading = GestureDetector(
        onTap: onView,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: DocThumbImage(
              url: thumbnailUrl,
              bytes: thumbnail,
              width: 38,
              height: 38,
              fit: BoxFit.cover,
              placeholder: _box(p,
                  AppIcon(AppAssets.document, size: 18, color: AppColors.purple))),
        ),
      );
    } else {
      leading = _box(p,
          AppIcon(AppAssets.document, size: 18, color: AppColors.purple));
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: p.fieldBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.fieldBorder),
      ),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            // Every pre-disbursal document is mandatory → red " *".
            child: Text.rich(TextSpan(children: [
              TextSpan(
                  text: label,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: p.title)),
              const TextSpan(
                  text: ' *',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.statusRed)),
            ])),
          ),
          const SizedBox(width: 8),
          if (busy)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.purple),
            )
          else if (uploaded)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: AppColors.success),
                  child: const Icon(Icons.check, size: 16, color: Colors.white),
                ),
                GestureDetector(
                  onTap: onRemove,
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.only(left: 6, right: 2),
                    child: Icon(Icons.close,
                        size: 18, color: AppColors.statusRed),
                  ),
                ),
              ],
            )
          else
            OutlinedButton(
              onPressed: onUpload,
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Upload',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary)),
            ),
        ],
      ),
    );
  }

  Widget _box(dynamic p, Widget child) => Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.purple.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(9),
        ),
        child: child,
      );
}

/// Fullscreen in-app PDF viewer.
class _PdfViewer extends StatelessWidget {
  const _PdfViewer({required this.path});
  final String path;

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
      body: PDFView(filePath: path, swipeHorizontal: false),
    );
  }
}

/// Asset Details card — owner, model, manufacturer, chassis, engine, from the
/// details response's `assetDetails`.
class _AssetDetailsCard extends StatelessWidget {
  const _AssetDetailsCard({required this.asset});
  final AssetDetails? asset;

  // "2025-01-01" → "01 Jan 2025" (leaves other shapes as-is).
  static String _fmtDate(String v) {
    final s = v.trim();
    if (s.isEmpty) return s;
    final p = s.split('T').first.split('-');
    if (p.length == 3 && p[0].length == 4) {
      const m = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      final mi = int.tryParse(p[1]) ?? 0;
      if (mi >= 1 && mi <= 12) return '${p[2]} ${m[mi - 1]} ${p[0]}';
    }
    return v;
  }

  @override
  Widget build(BuildContext context) {
    return FlowCard(
      heading: 'Asset Details',
      child: Column(
        children: [
          DetailRow(label: 'Owner Name', value: asset?.ownerName ?? ''),
          DetailRow(label: 'Model Number', value: asset?.modelNumber ?? ''),
          DetailRow(
              label: 'Manufacturer Name', value: asset?.manufacturerName ?? ''),
          DetailRow(
              label: 'Manufacturer Date',
              value: _fmtDate(asset?.manufacturerDate ?? '')),
          DetailRow(
            label: 'Chassis Number',
            valueWidget: Builder(builder: (context) {
              final p = context.palette;
              final chassis = (asset?.chassisNumber ?? '').trim();
              final status = (asset?.chassisStatus ?? '').trim();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(chassis.isEmpty ? '—' : chassis,
                      style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                          color: p.title)),
                  if (status.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.purple.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      // Capitalize for display (e.g. "new" → "New").
                      child: Text(
                          status[0].toUpperCase() + status.substring(1),
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.purple)),
                    ),
                  ],
                ],
              );
            }),
          ),
          DetailRow(
              label: 'Motor Serial/Engine Number',
              value: asset?.engineNumber ?? ''),
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
