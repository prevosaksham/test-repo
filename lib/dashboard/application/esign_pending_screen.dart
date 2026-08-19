import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/device/app_device.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/models/financial_approval.dart';
import '../../data/models/lead_item.dart';
import '../../data/repositories/application_repository.dart';
import '../../data/repositories/lead_repository.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_colors.dart';
import '../viewlead/view_lead_details_tab.dart' show LeadDocPdfViewer;
import 'application_flow_ui.dart';
import 'financial_documents_screen.dart';
import 'pre_disbursal_requirements_screen.dart';

/// eSign screen — pending/success driven by the details API's `esign.esigned`
/// (parsed into `allSigned`):
///   • false → "eSign Pending"  (Proceed enabled, awaiting signature)
///   • true  → "eSign Success"  (green, Date & Time, View Documents + Proceed)
/// The descriptive title/desc/date still come from `POST /field-verification/details`.
class ESignPendingScreen extends StatefulWidget {
  const ESignPendingScreen({super.key, required this.lead, this.previewSigned});
  final LeadItem lead;
  // TEMP PREVIEW ONLY: when non-null, skip the API and force pending/success.
  final bool? previewSigned;

  @override
  State<ESignPendingScreen> createState() => _ESignPendingScreenState();
}

class _ESignPendingScreenState extends State<ESignPendingScreen> {
  final _repo = LeadRepository();
  final ApplicationRepository _appRepo = ApplicationRepository();
  bool _loading = true;
  String? _error;
  FinancialApproval? _data;
  bool _initiatingEsign = false; // Initiate eSign call in progress
  bool _savingQuestions = false; // save-questions call in progress (Success bar)
  bool _savingManual = false; // manual-esign call in progress (Pending bar)

  // Disbursement Validation answers, keyed by the question `key`. Seeded from
  // the API (disbursementQuestions[].answer) and toggled locally via the radios.
  final Map<String, bool?> _validationAnswers = {};

  // Physically-signed documents to upload (Pending state) — (display name, API
  // document code sent to /application/upload).
  static const List<(String, String)> _uploadDocs = [
    ('Loan Agreement', 'MANUAL_LOAN_AGREEMENT'),
    ('KFS', 'MANUAL_KFS'),
    ('Sanction Letter', 'MANUAL_SANCTION_LETTER'),
  ];

  static const List<String> _allowedExt = ['pdf', 'png', 'jpg', 'jpeg'];
  static const int _maxUploadBytes = 10 * 1024 * 1024; // 10 MB

  // Per-document upload state, keyed by the API document code.
  final Map<String, String> _docNames = {}; // code -> uploaded file name
  final Map<String, String> _docPaths = {}; // code -> local file path
  final Map<String, String> _docUrls = {}; // code -> server file url (for view)
  final Set<String> _docUploading = {}; // codes uploading right now
  final Set<String> _docRemoving = {}; // codes being removed right now
  final Set<String> _docViewing = {}; // codes whose server file is being fetched

  // Proceed (Pending state) enables only once EVERY signed document is uploaded.
  bool get _allDocsUploaded =>
      _uploadDocs.every((d) => _docNames.containsKey(d.$2));

  // Proceed (Success state) enables only once EVERY Disbursement Validation
  // question has an answer (Yes or No), AND — when the Debit Card is "No" — the
  // mNACH document has been uploaded. No questions → nothing to answer.
  bool get _allValidationsAnswered {
    final questions = _data?.disbursementQuestions ?? const [];
    if (!questions.every((q) => _validationAnswers[q.key] != null)) return false;
    // Debit Card unavailable (No) → mNACH must be uploaded before Proceed.
    if (_validationAnswers['hasDebitCard'] == false &&
        !_docNames.containsKey('mNACH')) {
      return false;
    }
    return true;
  }

  // Success-bar Proceed label follows the Debit Card answer: available (Yes) →
  // eNACH, not available (No) → mNACH; else the plain "Proceed".
  String get _proceedLabel {
    final debit = _validationAnswers['hasDebitCard'];
    if (debit == true) return 'Proceed';
    if (debit == false) return 'Proceed';
    return 'Proceed';
  }

  // Pending / success is driven by the details API's `esign.esigned`
  // (parsed into `allSigned`): false → "eSign Pending", true → "eSign Success".
  bool get _signed => widget.previewSigned ?? (_data?.allSigned ?? false);
  String get _title => _data?.esignTitle ?? '';
  String get _desc => _data?.esignDesc ?? '';
  String get _dateLabel => widget.previewSigned == true && _data == null
      ? _fmtEsignDate('2024-05-20T11:42:00')
      : _fmtEsignDate(_data?.esignDate ?? '');

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  // ISO datetime from the API → "20 May 2024, 11:42 AM" in the device's local
  // zone. Anything unparseable (e.g. an already-formatted string) is shown as-is.
  static String _fmtEsignDate(String v) {
    final s = v.trim();
    final dt = DateTime.tryParse(s)?.toLocal();
    if (dt == null) return s;
    final h12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final meridiem = dt.hour < 12 ? 'AM' : 'PM';
    return '${dt.day.toString().padLeft(2, '0')} ${_months[dt.month - 1]} '
        '${dt.year}, $h12:$minute $meridiem';
  }

  @override
  void initState() {
    super.initState();
    if (widget.previewSigned == null) {
      _load();
    } else {
      _loading = false; // preview: skip the API, render the static UI
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _repo.getFinancialApproval(leadId: widget.lead.id);
      if (!mounted) return;
      setState(() {
        _data = data;
        _applyManualDocs(data); // pre-fill already-uploaded signed documents
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

  // Reflect the manualDocuments[] slots from /field-verification/details — mark
  // any already-uploaded signed document as uploaded (so it shows done and
  // Proceed enables). Runs inside setState in _load.
  void _applyManualDocs(FinancialApproval data) {
    for (final m in data.manualDocuments) {
      if (m.uploaded && m.documentCode.isNotEmpty) {
        _docNames[m.documentCode] =
            m.name.isNotEmpty ? m.name : m.documentCode;
        if (m.url.trim().isNotEmpty) _docUrls[m.documentCode] = m.url.trim();
      }
    }
    // Uploaded mNACH document (data.mNACH) → mark it uploaded too.
    final mnach = data.mnach;
    if (mnach != null && mnach.uploaded) {
      _docNames['mNACH'] = mnach.name.isNotEmpty ? mnach.name : 'mNACH';
      if (mnach.url.trim().isNotEmpty) _docUrls['mNACH'] = mnach.url.trim();
    }
    // Seed the Disbursement Validation radios from the saved answers.
    for (final q in data.disbursementQuestions) {
      if (q.key.isNotEmpty) _validationAnswers[q.key] = q.answer;
    }
    // A mNACH document only exists when the Debit Card is unavailable, so when
    // one is uploaded default the Debit Card answer to "No" (unless the API
    // already sent an explicit answer).
    if (_docNames.containsKey('mNACH') &&
        _validationAnswers['hasDebitCard'] == null) {
      _validationAnswers['hasDebitCard'] = false;
    }
    // TEMP DEBUG: verify the mNACH / questions parse.
    debugPrint('[eSign] mnach.uploaded=${data.mnach?.uploaded} '
        'mnach.url=${data.mnach?.url} '
        'questions=${data.disbursementQuestions.length} '
        'docNames[mNACH]=${_docNames.containsKey('mNACH')} '
        'hasDebitCard=${_validationAnswers['hasDebitCard']}');
  }

  // Proceed → Pre-Disbursal Requirements (enabled in both pending & success).
  void _proceed() => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PreDisbursalRequirementsScreen(lead: widget.lead),
        ),
      );

  // Pending-state Proceed (manual e-sign): the RM uploaded the signed documents,
  // so complete the manual e-sign (POST /application/esign/manual) and only
  // advance on a success response.
  Future<void> _proceedManual() async {
    if (_savingManual) return;
    final appId = _applicationIdInt;
    if (appId == null) {
      _toastErr('Application ID not found. Please try again.');
      return;
    }
    final stageId = _esignStageId;
    if (stageId == null) {
      _toastErr('eSign stage not found. Please try again.');
      return;
    }
    // TEMP: manual e-sign API commented — just log the payload that would be
    // sent to /application/esign/manual (applicationId + stageId + uploaded docs).
    debugPrint('[Pending Proceed / Manual eSign] applicationId=$appId, '
        'stageId=$stageId, uploadedDocs=${_docNames.keys.toList()}');
    setState(() => _savingManual = true);
    try {
      final res = await _appRepo.manualEsign(applicationId: appId, stageId: stageId);
      if (!mounted) return;
      final ok = res is Map && (res['success'] == true || res['status'] == true);
      final msg = (res is Map &&
              res['message'] is String &&
              (res['message'] as String).trim().isNotEmpty)
          ? (res['message'] as String).trim()
          : null;
      if (!ok) {
        _toastErr(msg ?? 'Could not complete manual e-sign. Please try again.');
        return;
      }
      if (msg != null) AppToast.show(context, msg, type: ToastType.success);
      // eSign is now done → DON'T navigate. Re-fetch so the screen switches to
      // "Documents Signed Successfully" (esigned = true) with the Disbursement
      // Validations; the RM answers those, then Proceed → Pre-Disbursal.
      setState(() => _savingManual = false);
      await _load();
      return;
    } on ApiException catch (e) {
      if (mounted) _toastErr(e.message);
    } catch (_) {
      if (mounted) _toastErr('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _savingManual = false);
    }
  }

  // Success-state Proceed: save the Disbursement Validation answers
  // (POST /loan-application/questions) and only advance on a success response.
  Future<void> _proceedSuccess() async {
    if (_savingQuestions) return;
    final questions = _data?.disbursementQuestions ?? const [];
    // No validations → nothing to save, go straight ahead.
    if (questions.isEmpty) {
      _proceed();
      return;
    }
    final appId = _applicationIdInt;
    if (appId == null) {
      _toastErr('Application ID not found. Please try again.');
      return;
    }
    // Both flows (eNACH = Debit Card Yes, mNACH = No) send the eNACH stage id
    // (21) — the backend requires stageId to be a number.
    final isEnach = _validationAnswers['hasDebitCard'] == true;
    final int? stageId = _enachStageId;
    if (stageId == null) {
      _toastErr('Stage not found. Please try again.');
      return;
    }
    // Every question must be answered before proceeding.
    final payload = <Map<String, dynamic>>[];
    for (final q in questions) {
      final a = _validationAnswers[q.key];
      if (a == null) {
        _toastErr('Please answer all disbursement validations.');
        return;
      }
      payload.add({'key': q.key, 'answer': a});
    }
    // What goes to /loan-application/questions (both flows → eNACH stage 21).
    debugPrint('[Initiate ${isEnach ? 'eNACH' : 'mNACH'}] applicationId=$appId, '
        'stageId=$stageId, questions=$payload');
    setState(() => _savingQuestions = true);
    try {
      final res = await _appRepo.saveLoanQuestions(
          applicationId: appId, stageId: stageId, questions: payload);
      if (!mounted) return;
      final ok = res is Map && (res['success'] == true || res['status'] == true);
      final msg = (res is Map &&
              res['message'] is String &&
              (res['message'] as String).trim().isNotEmpty)
          ? (res['message'] as String).trim()
          : null;
      if (!ok) {
        _toastErr(msg ?? 'Could not save validations. Please try again.');
        return;
      }
      if (msg != null) AppToast.show(context, msg, type: ToastType.success);
      _proceed(); // advance only on success
    } on ApiException catch (e) {
      if (mounted) _toastErr(e.message);
    } catch (_) {
      if (mounted) _toastErr('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _savingQuestions = false);
    }
  }

  void _viewDocuments() => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FinancialDocumentsScreen(lead: widget.lead),
        ),
      );

  // Exit clears the application stack and lands on Home, same as every other
  // screen in the flow.
  void _exit() => Navigator.of(context)
      .pushNamedAndRemoveUntil(AppRoutes.home, (r) => false);

  // applicationId for the eSign call — from /field-verification/details'
  // applicantDetails. Prefer `applicationId`; when that's empty the id lives in
  // `id` (e.g. "365"); finally fall back to the lead's applicationId.
  int? get _applicationIdInt {
    final a = _data?.applicant;
    final appId = int.tryParse((a?.applicationId ?? '').trim());
    final id = int.tryParse((a?.id ?? '').trim());
    return appId ?? id ?? widget.lead.applicationId;
  }

  // stageId of the eSign stage (stages[] `ESIGN_STATUS`, e.g. 19), falling back
  // to the active stage. Sent on both the manual-esign and save-questions calls.
  int? get _esignStageId {
    final stage = _data?.stageByKey('ESIGN_STATUS') ?? _data?.currentStage;
    return int.tryParse(stage?.stageId ?? '');
  }

  // eNACH stage id (stages[] `eNACH`, e.g. 21) — used for the "Initiate eNACH"
  // flow (Debit Card available).
  int? get _enachStageId {
    final stage = _data?.stageByKey('eNACH');
    return int.tryParse(stage?.stageId ?? '');
  }

  // "Initiate eSign" → POST /application/esign/initiate-multi { applicationId }.
  // The server's message is shown as a toast (green on success, red on error).
  Future<void> _initiateEsign() async {
    if (_initiatingEsign) return;
    final appId = _applicationIdInt;
    if (appId == null) {
      AppToast.show(context, 'Application ID not found. Please try again.',
          type: ToastType.error);
      return;
    }
    setState(() => _initiatingEsign = true);
    try {
      final res = await _appRepo.initiateEsignMulti(applicationId: appId);
      if (!mounted) return;
      final ok = res is Map && (res['success'] == true || res['status'] == true);
      final msg = (res is Map &&
              res['message'] is String &&
              (res['message'] as String).trim().isNotEmpty)
          ? (res['message'] as String).trim()
          : (ok
              ? 'eSign initiated successfully.'
              : 'Could not initiate eSign. Please try again.');
      AppToast.show(context, msg,
          type: ok ? ToastType.success : ToastType.error);
    } on ApiException catch (e) {
      if (mounted) AppToast.show(context, e.message, type: ToastType.error);
    } catch (_) {
      if (mounted) {
        AppToast.show(context, 'Something went wrong. Please try again.',
            type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _initiatingEsign = false);
    }
  }

  // ===== Signed-document upload (same flow as the Upload Documents screen) =====
  // Sheet: Choose File (PDF/image) / Camera / Gallery. Images are cropped, the
  // 10 MB cap is enforced, then the file is sent via POST /application/upload.
  Future<void> _showDocUploadSheet(String code) async {
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
                  style: TextStyle(color: p.title, fontWeight: FontWeight.w600)),
              subtitle: Text('Single PDF or image (png/jpg/jpeg) · max 10MB',
                  style: TextStyle(color: p.subtitle, fontSize: 12)),
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera, color: AppColors.purple),
              title: Text('Camera',
                  style: TextStyle(color: p.title, fontWeight: FontWeight.w600)),
              subtitle: Text('Capture a document photo · max 10MB',
                  style: TextStyle(color: p.subtitle, fontSize: 12)),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.photo_library, color: AppColors.purple),
              title: Text('Gallery',
                  style: TextStyle(color: p.title, fontWeight: FontWeight.w600)),
              subtitle: Text('Pick an image from the gallery · max 10MB',
                  style: TextStyle(color: p.subtitle, fontSize: 12)),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == 'file') {
      await _pickDocFile(code);
    } else if (choice == 'camera') {
      await _pickDocImage(code, ImageSource.camera);
    } else if (choice == 'gallery') {
      await _pickDocImage(code, ImageSource.gallery);
    }
  }

  Future<void> _pickDocFile(String code) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _allowedExt,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return; // cancelled
      final f = result.files.first;
      final ext = (f.extension ?? '').toLowerCase();
      if (!_allowedExt.contains(ext)) {
        _toastErr('Sirf PDF ya image (png/jpg/jpeg) upload ho sakti hai');
        return;
      }
      if (f.path == null) {
        _toastErr('File select nahi hui, dobara try karein');
        return;
      }
      if (ext == 'pdf' && f.size > _maxUploadBytes) {
        _toastErr('Please upload PDF 10 MB or below');
        return;
      }
      await _onDocPicked(code, f.path!, f.name, ext);
    } catch (_) {
      _toastErr('File select nahi hui, dobara try karein');
    }
  }

  Future<void> _pickDocImage(String code, ImageSource source) async {
    try {
      final img = await ImagePicker().pickImage(source: source);
      if (img == null) return; // cancelled
      final ext = img.name.contains('.')
          ? img.name.split('.').last.toLowerCase()
          : 'jpg';
      await _onDocPicked(code, img.path, img.name, ext);
    } catch (_) {
      _toastErr(source == ImageSource.camera
          ? 'Camera nahi khula, dobara try karein'
          : 'Gallery nahi khuli, dobara try karein');
    }
  }

  // Image → crop then enforce the size cap; PDF goes straight to upload.
  Future<void> _onDocPicked(
      String code, String path, String name, String ext) async {
    final isImage = ext == 'png' || ext == 'jpg' || ext == 'jpeg';
    var usePath = path;
    var useName = name;
    if (isImage) {
      final cropped = await _cropDocImage(path);
      if (cropped == null) return; // user cancelled the crop
      usePath = cropped;
      useName = cropped.split(Platform.pathSeparator).last;
      final size = await File(cropped).length();
      if (size > _maxUploadBytes) {
        _toastErr('Please upload image 10 MB or below');
        return;
      }
      if (!mounted) return;
    }
    await _uploadDoc(code, usePath, useName);
  }

  Future<String?> _cropDocImage(String path) async {
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
        ),
        IOSUiSettings(
          title: 'Crop Image',
          aspectRatioLockEnabled: false,
          resetAspectRatioEnabled: true,
          aspectRatioPickerButtonHidden: false,
        ),
      ],
    );
    return cropped?.path;
  }

  // Upload one signed document (POST /application/upload, { leadId, CODE: file }).
  Future<void> _uploadDoc(String code, String path, String name) async {
    setState(() => _docUploading.add(code));
    try {
      final res = await _appRepo
          .uploadFiles(leadId: widget.lead.id, files: {code: path});
      if (!mounted) return;
      final ok = res is Map && (res['success'] == true || res['status'] == true);
      final msg = (res is Map &&
              res['message'] is String &&
              (res['message'] as String).trim().isNotEmpty)
          ? (res['message'] as String).trim()
          : (ok ? 'Document uploaded' : 'Upload failed');
      if (ok) {
        setState(() {
          _docNames[code] = name;
          _docPaths[code] = path;
        });
        AppToast.show(context, msg, type: ToastType.success);
      } else {
        AppToast.show(context, msg, type: ToastType.error);
      }
    } on ApiException catch (e) {
      if (mounted) _toastErr(e.message);
    } catch (_) {
      if (mounted) _toastErr('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _docUploading.remove(code));
    }
  }

  // Remove an uploaded signed document — delete on the server, then clear.
  Future<void> _removeDoc(String code) async {
    if (_docRemoving.contains(code)) return;
    setState(() => _docRemoving.add(code));
    try {
      await _appRepo.deleteDocument(leadId: widget.lead.id, docCode: code);
      if (!mounted) return;
      setState(() {
        _docNames.remove(code);
        _docPaths.remove(code);
        _docUrls.remove(code);
      });
    } on ApiException catch (e) {
      if (mounted) _toastErr(e.message);
    } catch (_) {
      if (mounted) _toastErr('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _docRemoving.remove(code));
    }
  }

  // Tap an uploaded document's thumbnail → view it. Fresh local files open
  // straight away; a server file (from manualDocuments url) is fetched first.
  Future<void> _viewDoc(String code) async {
    final path = _docPaths[code];
    if (path != null) {
      if (path.toLowerCase().endsWith('.pdf')) {
        _openPdfPath(path);
      } else {
        _showImagePreview(FileImage(File(path)));
      }
      return;
    }
    final url = (_docUrls[code] ?? '').trim();
    if (!url.startsWith('http') || _docViewing.contains(code)) return;
    setState(() => _docViewing.add(code));
    try {
      final bytes = await _repo.documentBytesFromUrl(url);
      if (!mounted) return;
      if (url.toLowerCase().endsWith('.pdf')) {
        final dir = await Directory.systemTemp.createTemp('esign_doc');
        final f = File('${dir.path}/document.pdf');
        await f.writeAsBytes(bytes, flush: true);
        if (!mounted) return;
        _openPdfPath(f.path);
      } else {
        _showImagePreview(MemoryImage(bytes));
      }
    } on ApiException catch (e) {
      if (mounted) _toastErr(e.message);
    } catch (_) {
      if (mounted) _toastErr('Could not open this document.');
    } finally {
      if (mounted) setState(() => _docViewing.remove(code));
    }
  }

  void _openPdfPath(String path) => Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => LeadDocPdfViewer(path: path),
        ),
      );

  // Full-screen image preview with a close button.
  void _showImagePreview(ImageProvider image) {
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
              child: InteractiveViewer(child: Image(image: image)),
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

  void _toastErr(String msg) =>
      AppToast.show(context, msg, type: ToastType.error);

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AppFlowScaffold(
        title: 'eSign Pending',
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return AppFlowScaffold(
        title: 'eSign Pending',
        body: _ErrorView(message: _error!, onRetry: _load),
      );
    }
    final signed = _signed;
    return AppFlowScaffold(
      title: signed ? 'eSign Success' : 'eSign Pending',
      bottomBar: signed
          // Success → View Document + (Exit | Proceed). Proceed saves the
          // Disbursement Validation answers first (only advances on success).
          ? _SuccessBar(
              onView: _viewDocuments,
              onProceed: _proceedSuccess,
              onExit: _exit,
              proceeding: _savingQuestions,
              proceedEnabled: _allValidationsAnswered,
              proceedLabel: _proceedLabel)
          // Pending → Exit + Proceed. Enabled once all signed docs are uploaded;
          // tapping completes the manual e-sign (only advances on success).
          : _ProceedBar(
              enabled: _allDocsUploaded && !_savingManual,
              proceeding: _savingManual,
              onTap: _proceedManual,
              onExit: _exit),
      body: _buildBody(signed),
    );
  }

  // ===== Body — static UI matching the eSign Pending / Success designs =====
  Widget _buildBody(bool signed) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
      children: signed ? _successSections() : _pendingSections(),
    );
  }

  // ---- Pending ----
  List<Widget> _pendingSections() {
    final p = context.palette;
    final titleText =
        _title.isNotEmpty ? _title : 'Documents yet to be signed';
    final descText =
        _desc.isNotEmpty ? _desc : 'Your documents are pending signature.';
    return [
      const Center(
          child: _Badge(inner: AppColors.amber, icon: Icons.priority_high)),
      const SizedBox(height: 22),
      Text(titleText,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 21, fontWeight: FontWeight.w700, color: p.title)),
      const SizedBox(height: 10),
      Text(descText,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, height: 1.4, color: p.subtitle)),
      const SizedBox(height: 26),
      _proceedWithEsignCard(),
      const SizedBox(height: 18),
      _orDivider(),
      const SizedBox(height: 18),
      _documentsUploadCard(),
    ];
  }

  // ---- Success ----
  List<Widget> _successSections() {
    final p = context.palette;
    final titleText =
        _title.isNotEmpty ? _title : 'Documents Signed Successfully!';
    final descText = _desc.isNotEmpty
        ? _desc
        : 'Your documents have been eSigned successfully.';
    return [
      const Center(child: _Badge(inner: AppColors.success, icon: Icons.check)),
      const SizedBox(height: 22),
      Text(titleText,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 21, fontWeight: FontWeight.w700, color: p.title)),
      const SizedBox(height: 10),
      Text(descText,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, height: 1.4, color: p.subtitle)),
      if (_dateLabel.isNotEmpty) ...[
        const SizedBox(height: 24),
        _dateTimeCard(),
      ],
      const SizedBox(height: 16),
      _disbursementValidationsCard(),
    ];
  }

  // ---- Shared pieces ----
  BoxDecoration _cardDeco() {
    final p = context.palette;
    return BoxDecoration(
      color: p.cardBg,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: p.fieldBorder),
    );
  }

  // Purple-tinted rounded tile holding a document/pen icon.
  Widget _iconTile(IconData icon, {double size = 40}) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.purple.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: size * 0.5, color: AppColors.purple),
    );
  }

  // Small orange outlined action button (Initiate eSign / Upload / Upload
  // mNACH). Shows a spinner and disables itself while [busy].
  Widget _outlineOrangeButton(String label, VoidCallback? onTap,
      {bool busy = false}) {
    return OutlinedButton(
      onPressed: busy ? null : onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.deepOrange,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: const BorderSide(color: AppColors.deepOrange),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.deepOrange))
          : Text(label,
              style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.deepOrange)),
    );
  }

  // A tinted info strip with a filled circular icon (neutral / purple / green /
  // amber) + text.
  Widget _infoBox({
    required Color accent,
    required IconData icon,
    required String text,
    Color? bg,
  }) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg ?? accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
            child: Icon(icon, size: 15, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(text,
                  style: TextStyle(
                      fontSize: 12.5, height: 1.4, color: p.subtitle)),
            ),
          ),
        ],
      ),
    );
  }

  // "Yes / No" radio pair. [value] is nullable — null means nothing selected.
  Widget _yesNoRow({
    required bool? value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        _radio('Yes', value == true, () => onChanged(true)),
        const SizedBox(width: 28),
        _radio('No', value == false, () => onChanged(false)),
      ],
    );
  }

  Widget _radio(String label, bool selected, VoidCallback onTap) {
    final p = context.palette;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? AppColors.purple : p.fieldBorder,
                width: selected ? 5 : 1.5,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 13.5, color: p.title)),
        ],
      ),
    );
  }

  // ---- Pending cards ----
  Widget _proceedWithEsignCard() {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _iconTile(Icons.drive_file_rename_outline),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Proceed with eSign',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: p.title)),
                    const SizedBox(height: 6),
                    Text(
                      'Facing issues with physical document upload? Proceed '
                      'with Aadhaar linked mobile number based eSign as an '
                      'alternate signing method.',
                      style: TextStyle(
                          fontSize: 12.5, height: 1.45, color: p.subtitle),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Initiate eSign button stays as-is; once the link is sent, a green
          // "eSign Link Sent" message shows beside it.
          Row(
            children: [
              _outlineOrangeButton('Initiate eSign', _initiateEsign,
                  busy: _initiatingEsign),
              if (_data?.esignLinkSent ?? false) ...[
                const SizedBox(width: 10),
                Flexible(child: _esignLinkSentLabel()),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // Green "eSign Link Sent" message shown next to the Initiate eSign button once
  // the link has been sent to the signer(s).
  Widget _esignLinkSentLabel() {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle, size: 16, color: AppColors.success),
        SizedBox(width: 6),
        Flexible(
          child: Text('eSign Link Sent',
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.success)),
        ),
      ],
    );
  }

  Widget _orDivider() {
    final p = context.palette;
    return Row(
      children: [
        Expanded(child: Divider(color: p.fieldBorder)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('OR',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: p.subtitle)),
        ),
        Expanded(child: Divider(color: p.fieldBorder)),
      ],
    );
  }

  Widget _documentsUploadCard() {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Documents Upload',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: p.title)),
          const SizedBox(height: 12),
          _infoBox(
            accent: Colors.grey.shade600,
            bg: p.fieldBg,
            icon: Icons.info,
            text: 'Please upload all physically signed documents to proceed '
                'further.',
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < _uploadDocs.length; i++) ...[
            _uploadRow(_uploadDocs[i].$1, _uploadDocs[i].$2),
            if (i != _uploadDocs.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _uploadRow(String name, String code) {
    final p = context.palette;
    final uploading = _docUploading.contains(code);
    final removing = _docRemoving.contains(code);
    final fileName = _docNames[code];
    final path = _docPaths[code];
    final uploaded = fileName != null;
    final isPdf = (path != null && path.toLowerCase().endsWith('.pdf')) ||
        (path == null && (_docUrls[code] ?? '').toLowerCase().endsWith('.pdf'));
    final viewing = _docViewing.contains(code);

    Widget leading;
    if (viewing) {
      leading = _iconTile(Icons.hourglass_empty, size: 36);
    } else if (uploaded && path != null && !isPdf) {
      leading = ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(File(path), width: 36, height: 36, fit: BoxFit.cover),
      );
    } else if (uploaded && isPdf) {
      leading = Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.statusRed.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.picture_as_pdf,
            size: 20, color: AppColors.statusRed),
      );
    } else {
      leading = _iconTile(Icons.insert_drive_file_outlined, size: 36);
    }
    // Uploaded → tapping the thumbnail views the document.
    if (uploaded) {
      leading = GestureDetector(
        onTap: viewing ? null : () => _viewDoc(code),
        child: leading,
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: p.fieldBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.fieldBorder),
      ),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: p.title)),
                if (uploaded && !uploading) ...[
                  const SizedBox(height: 2),
                  Text(fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.success)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (uploading || removing)
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                  strokeWidth: 2.4, color: AppColors.purple),
            )
          else if (uploaded) ...[
            const CircleAvatar(
              radius: 13,
              backgroundColor: AppColors.success,
              child: Icon(Icons.check, size: 16, color: Colors.white),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _removeDoc(code),
              child: Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.statusRed.withValues(alpha: 0.12),
                ),
                child: const Icon(Icons.close,
                    size: 16, color: AppColors.statusRed),
              ),
            ),
          ] else
            _outlineOrangeButton('Upload', () => _showDocUploadSheet(code)),
        ],
      ),
    );
  }

  // ---- Success cards ----
  Widget _dateTimeCard() {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Date & Time:',
              style: TextStyle(fontSize: 13, color: p.subtitle)),
          const SizedBox(height: 4),
          Text(_dateLabel,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: p.title)),
        ],
      ),
    );
  }

  Widget _disbursementValidationsCard() {
    final p = context.palette;
    final questions = _data?.disbursementQuestions ?? const <DisbursementQuestion>[];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Disbursement Validations',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: p.title)),
          if (questions.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('No validations to show.',
                  style: TextStyle(fontSize: 13.5, color: p.subtitle)),
            )
          else
            for (var i = 0; i < questions.length; i++) ...[
              if (i == 0)
                const SizedBox(height: 14)
              else ...[
                const SizedBox(height: 14),
                Divider(height: 1, color: p.fieldBorder),
                const SizedBox(height: 14),
              ],
              _validationQuestion(i + 1, questions[i]),
            ],
        ],
      ),
    );
  }

  // Debit Card radio change. Selecting "Yes" (card available) hides the mNACH
  // upload — if a mNACH doc is already uploaded, confirm removal first; on "Yes"
  // it's deleted (server) and the answer switches, on "No" nothing changes.
  Future<void> _onDebitCardChanged(String qKey, bool v) async {
    const code = 'mNACH';
    if (v == true && _docNames.containsKey(code)) {
      final ok = await _confirmRemoveMnach();
      if (!ok || !mounted) return; // keep the current selection
      await _removeDoc(code); // server delete + clear locally
      if (!mounted) return;
    }
    setState(() => _validationAnswers[qKey] = v);
  }

  Future<bool> _confirmRemoveMnach() async {
    final p = context.palette;
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Remove mNACH document?',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: p.title)),
        content: Text(
          'If the Debit Card is available, the uploaded mNACH document will be '
          'removed. Are you sure you want to remove it?',
          style: TextStyle(fontSize: 14, height: 1.4, color: p.subtitle),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('No',
                style: TextStyle(color: p.subtitle, fontWeight: FontWeight.w700)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.statusRed,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Yes',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  // mNACH upload (Debit Card question) — same flow as the signed documents
  // (Camera / Gallery / File + crop), sent under the "mNACH" document code.
  // Shows the "Upload mNACH" button until uploaded, then the uploaded row
  // (tappable thumbnail + Remove).
  Widget _mnachUpload() {
    const code = 'mNACH';
    final active = _docNames.containsKey(code) || _docUploading.contains(code);
    if (active) return _uploadRow('mNACH', code);
    return Align(
      alignment: Alignment.centerLeft,
      child: _outlineOrangeButton(
          'Upload mNACH', () => _showDocUploadSheet(code)),
    );
  }

  // One Disbursement Validation question: text + Yes/No radios + its checkpoint
  // box. The Debit Card question also shows an "Upload mNACH" button on "No".
  Widget _validationQuestion(int number, DisbursementQuestion q) {
    final p = context.palette;
    final answer = _validationAnswers[q.key];
    final isDebitCard = q.key == 'hasDebitCard';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$number. ${q.question}',
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: p.title)),
        const SizedBox(height: 8),
        _yesNoRow(
          value: answer,
          onChanged: isDebitCard
              ? (v) => _onDebitCardChanged(q.key, v)
              : (v) => setState(() => _validationAnswers[q.key] = v),
        ),
        // Debit Card → checkpoint (purple) + Upload mNACH shown only on "No"
        // (card unavailable). Other questions → green checkpoint always.
        if (q.checkpoint.isNotEmpty && (!isDebitCard || answer == false)) ...[
          const SizedBox(height: 12),
          _infoBox(
            accent: isDebitCard ? AppColors.purple : AppColors.success,
            icon: isDebitCard ? Icons.info : Icons.check,
            text: q.checkpoint,
            bg: AppColors.purple.withValues(alpha: 0.10),
          ),
        ],
        if (isDebitCard && answer == false) ...[
          const SizedBox(height: 12),
          _mnachUpload(),
        ],
      ],
    );
  }
}

/// Purple-tint circle with a filled inner badge (amber warning / green check).
class _Badge extends StatelessWidget {
  const _Badge({required this.inner, required this.icon});
  final Color inner;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.purple.withValues(alpha: 0.10),
      ),
      child: Container(
        width: 52,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: inner),
        child: Icon(icon, size: 30, color: Colors.white),
      ),
    );
  }
}

/// Pending bottom bar: outlined "Exit" (→ Home) over the gradient "Proceed"
/// button (dims while [enabled] is false).
class _ProceedBar extends StatelessWidget {
  const _ProceedBar({
    required this.enabled,
    required this.onTap,
    required this.onExit,
    this.proceeding = false,
  });
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onExit;
  final bool proceeding; // completing the manual e-sign

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + AppDevice.bottomNavGap),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.fieldBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _GradientButton(
                label: proceeding ? 'Processing…' : 'Proceed',
                enabled: enabled,
                onTap: onTap),
            const SizedBox(height: 10),
            _ExitButton(onExit: onExit),
          ],
        ),
      ),
    );
  }
}

/// Success bottom bar: outlined "View Documents" + gradient "Proceed" +
/// outlined "Exit" (→ Home).
class _SuccessBar extends StatelessWidget {
  const _SuccessBar({
    required this.onView,
    required this.onProceed,
    required this.onExit,
    this.proceeding = false,
    this.proceedEnabled = true,
    this.proceedLabel = 'Proceed',
  });
  final VoidCallback onView;
  final VoidCallback onProceed;
  final VoidCallback onExit;
  final bool proceeding; // saving the validation answers
  final bool proceedEnabled; // all validation questions answered
  final String proceedLabel; // Proceed / Initiate eNACH / Initiate mNACH

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + AppDevice.bottomNavGap),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.fieldBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton(
              onPressed: onView,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('View Documents',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary)),
            ),
            const SizedBox(height: 10),
            _GradientButton(
                label: proceeding ? 'Saving…' : proceedLabel,
                enabled: proceedEnabled && !proceeding,
                onTap: onProceed),
            const SizedBox(height: 10),
            _ExitButton(onExit: onExit),
          ],
        ),
      ),
    );
  }
}

/// Outlined "Exit" button — always returns to Home (clears the application
/// stack), matching every other screen in the flow.
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

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppColors.buttonGradient,
          borderRadius: BorderRadius.circular(12),
        ),
        child: ElevatedButton(
          onPressed: enabled ? onTap : null,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(label,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
        ),
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
