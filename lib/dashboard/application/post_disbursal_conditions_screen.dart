import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/models/lead_item.dart';
import '../../data/models/rc_dl_details.dart';
import '../../data/repositories/application_repository.dart';
import '../../data/repositories/doc_quality_repository.dart';
import '../../data/repositories/lead_repository.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_colors.dart';
import '../viewlead/view_lead_details_tab.dart' show LeadDocPdfViewer;
import '../widgets/interaction_ui.dart';
import 'application_flow_ui.dart';

/// Post-Disbursal Conditions — the final stage after disbursement: upload the
/// closing documents (RC Book, and, when applicable, Driving License + the
/// optional WCD Approval Letter) and Submit to complete the stage.
///
/// UI is fully wired for picking/cropping a file per document and showing its
/// uploaded state locally; the server upload/submit calls can be dropped into
/// [_uploadPath] / [_submit] once the endpoints are confirmed (same pattern as
/// PreDisbursalRequirementsScreen).
class PostDisbursalConditionsScreen extends StatefulWidget {
  const PostDisbursalConditionsScreen({
    super.key,
    required this.lead,
    this.stageId = '',
    this.applicationId = '',
  });
  final LeadItem lead;
  // Post-disbursal stage id — comes from the /application/disbursement-status
  // response and is sent back on Submit.
  final String stageId;
  // Numeric application id (data.id) — comes from the disbursement-status
  // response and is sent as applicationId on Submit.
  final String applicationId;

  @override
  State<PostDisbursalConditionsScreen> createState() =>
      _PostDisbursalConditionsScreenState();
}

// (code, title, subtitle, icon, enabled, required)
// RC Book and Driving License are BOTH mandatory — each shows a red `*` and
// Submit stays disabled until both are uploaded. WCD Approval stays optional.
const _kDocs = <_DocSpec>[
  _DocSpec(
    code: 'RC_BOOK',
    title: 'RC Book',
    subtitle: 'Upload the RC Book copy',
    icon: Icons.badge_outlined,
    required: true,
  ),
  _DocSpec(
    code: 'DRIVING_LICENCE',
    title: 'Driving License',
    subtitle: 'Upload the Driving License copy',
    icon: Icons.badge_outlined,
    required: true,
  ),
  _DocSpec(
    code: 'WCD',
    title: 'WCD Approval Letter',
    subtitle: '(Optional)',
    icon: Icons.description_outlined,
  ),
];

class _PostDisbursalConditionsScreenState
    extends State<PostDisbursalConditionsScreen> {
  final _appRepo = ApplicationRepository();
  final _docQuality = DocQualityRepository();
  final Map<String, String> _uploaded = {}; // doc code -> local file path
  final Set<String> _busy = {}; // doc codes currently picking/uploading

  // From /application/disbursement-status: stageId (data.stages[].id) +
  // applicationId (data.id). Seeded from any passed value, then refreshed.
  String _stageId = '';
  String _applicationId = '';

  // Review-section details. NOT passed into this screen — they are fetched from
  // `POST /field-verification/rc-dl-details` AFTER the RC Book is uploaded and
  // verified (RC block from the RC Book OCR, DL block from the DL OCR). Until
  // then the rows show "—".
  RcDlDetails? _rcDl;
  bool _submitting = false;
  bool _verifying = false; // manual RC verify call in progress

  @override
  void initState() {
    super.initState();
    _stageId = widget.stageId.trim();
    _applicationId = widget.applicationId.trim();
    _loadStatus();
    // Pre-fill any RC/DL details already uploaded & verified earlier, so a
    // returning user sees them straight away (also re-fetched after upload).
    _loadRcDlDetails();
  }

  // RC + DL details from the field-verification API — pre-filled on open and
  // re-fetched after each RC/DL upload + verify. A failure is non-fatal: the
  // rows stay "—".
  Future<void> _loadRcDlDetails() async {
    final appId = int.tryParse(_applicationId.trim());
    if (appId == null) return;
    try {
      final details = await _appRepo.rcDlDetails(applicationId: appId);
      if (!mounted) return;
      setState(() => _rcDl = details);
    } catch (_) {/* keep rows as "—" */}
  }

  // Server file url for a doc code (already-uploaded RC/DL) → shows it as
  // uploaded + viewable in the upload row.
  String _serverUrlFor(String code) {
    switch (code) {
      case 'RC_BOOK':
        return _rcDl?.rcUrl ?? '';
      case 'DRIVING_LICENCE':
        return _rcDl?.dlUrl ?? '';
      default:
        return '';
    }
  }

  // Silently fetch stageId + applicationId from the disbursement-status API.
  Future<void> _loadStatus() async {
    try {
      final leadId = int.tryParse(widget.lead.id.trim()) ?? widget.lead.id;
      final status = await _appRepo.getDisbursementStatus(leadId: leadId);
      if (!mounted) return;
      final hadAppId = _applicationId.trim().isNotEmpty;
      setState(() {
        if (status.stageId.trim().isNotEmpty) _stageId = status.stageId.trim();
        if (status.applicationId.trim().isNotEmpty) {
          _applicationId = status.applicationId.trim();
        }
      });
      // If the applicationId only became available now, pull the RC/DL details.
      if (!hadAppId && _applicationId.trim().isNotEmpty) _loadRcDlDetails();
    } catch (_) {/* keep any value passed in */}
  }
//735
  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: error ? AppColors.statusRed : AppColors.success,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // Tapping Upload opens a sheet: pick a PDF/image file OR capture from camera.
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

  Future<void> _capturePhoto(String code) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.camera);
    if (picked == null || !mounted) return;
    final cropped = await _cropImage(picked.path);
    if (cropped == null || !mounted) return;
    await _uploadPath(code, cropped);
  }

  // Free/manual cropper — same config as the other document screens.
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

  // Digio id_type a row expects. Only the Driving License row holds a detectable
  // ID card — RC Book and the WCD Approval Letter are not ID documents, so Digio
  // has nothing to match them against and they skip the check.
  static const Map<String, String> _expectedIdTypes = {
    'DRIVING_LICENCE': 'DRIVING_LICENSE',
  };

  static bool _isImagePath(String path) {
    final p = path.toLowerCase();
    return p.endsWith('.jpg') || p.endsWith('.jpeg') || p.endsWith('.png');
  }

  // Same guard as the Upload Documents screen (`_onPicked`): before sending the
  // file up, ask Digio what the image actually IS. A blurred/black-and-white
  // image, or anything that is not a Driving License in the DL row (a PAN, an RC
  // photo, …), is rejected here and never reaches the server. PDFs and the
  // non-ID rows skip the call. Returns false → do not upload.
  Future<bool> _passesIdCheck(String code, String path) async {
    final expType = _expectedIdTypes[code] ?? '';
    if (expType.isEmpty || !_isImagePath(path)) return true;
    try {
      final res = await _docQuality.analyzeIdCard(
        filePath: path,
        expectedIds: [expType],
        fileName: path.split(Platform.pathSeparator).last,
      );
      if (!mounted) return false;
      // 1) Image quality first — blurred / black-and-white?
      if (!res.qualityPassed) {
        _showDocErrorDialog(
          'Poor Image Quality',
          '${_titleFor(code)} image is not in good quality. Please upload a '
              'proper image.',
        );
        return false;
      }
      // 2) Then the document type — is this really a Driving License?
      if (res.detectedIdType != expType) {
        _showDocErrorDialog(
          'Wrong Document',
          _wrongTypeMessage(code, res.detectedIdType),
        );
        return false;
      }
      return true;
    } on ApiException catch (e) {
      // Technical failure (no internet / API error) — not a quality verdict.
      if (mounted) _snack(e.message, error: true);
      return false;
    }
  }

  // Friendly name for a Digio id_type code.
  String _idTypeLabel(String idType) {
    switch (idType) {
      case 'AADHAAR':
        return 'Aadhaar Card';
      case 'VOTER_ID':
        return 'Voter ID';
      case 'PAN':
        return 'PAN Card';
      case 'DRIVING_LICENSE':
        return 'Driving License';
      default:
        return '';
    }
  }

  String _wrongTypeMessage(String code, String detected) {
    final expected = _titleFor(code);
    final detectedLabel = _idTypeLabel(detected);
    if (detectedLabel.isEmpty) {
      return 'Could not recognize this as $expected. Please upload a valid '
          '$expected image.';
    }
    return 'This looks like a $detectedLabel. Please upload your $expected.';
  }

  void _showDocErrorDialog(String title, String message) {
    final p = context.palette;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.statusRed),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: p.title)),
            ),
          ],
        ),
        content: Text(message,
            style: TextStyle(fontSize: 14, color: p.subtitle, height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK',
                style: TextStyle(
                    color: AppColors.purple, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // Upload the chosen file to the server via the shared /application/upload API
  // (same as the Upload Documents screen) — the doc code (RC_BOOK / WCD_APPROVAL
  // / …) is the multipart field name. Marks the row uploaded only on success.
  Future<void> _uploadPath(String code, String path) async {
    setState(() => _busy.add(code));
    try {
      // Wrong document in the row → stop here, nothing goes to the server.
      if (!await _passesIdCheck(code, path)) return;
      if (!mounted) return;
      final res =
          await _appRepo.uploadFiles(leadId: widget.lead.id, files: {code: path});
      if (!mounted) return;
      // A 200 can still carry an application-level failure (success:false) — only
      // proceed on a genuine success. Treat the response as failed ONLY when the
      // flag is EXPLICITLY false, so a plain success payload (no flag) still
      // counts as success.
      if (res is Map && (res['success'] == false || res['status'] == false)) {
        final msg = (res['message'] is String &&
                (res['message'] as String).trim().isNotEmpty)
            ? (res['message'] as String).trim()
            : '${_titleFor(code)} upload failed';
        _snack(msg, error: true);
        return; // don't mark uploaded, don't verify
      }
      setState(() => _uploaded[code] = path);
      _snack('${_titleFor(code)} uploaded');
      // DL data is available right after upload → refresh it IN-PLACE (setState,
      // no page reload) so the DL details fill in immediately. RC details only
      // appear after the manual "Verify RC", so RC upload doesn't auto-fetch.
      if (code == 'DRIVING_LICENCE') {
        await _loadRcDlDetails();
      }
    } catch (e) {
      _snack(e.toString().replaceFirst('ApiException: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(code));
    }
  }

  /// After an RC Book / DL upload succeeds, call `POST /loan-application/verify`
  /// with the applicationId. The server owns the outcome — its message is shown
  /// as-is (green on success, red on failure).
  Future<void> _verifyRc() async {
    if (_verifying) return;
    final appId = int.tryParse(_applicationId.trim());
    if (appId == null) {
      _snack('Cannot verify yet — application id not available.', error: true);
      return;
    }
    setState(() => _verifying = true);
    try {
      final res = await _appRepo.verifyLoanApplication(applicationId: appId);
      if (!mounted) return;
      final ok = res is Map && (res['success'] == true || res['status'] == true);
      final msg = (res is Map &&
              res['message'] is String &&
              (res['message'] as String).trim().isNotEmpty)
          ? (res['message'] as String).trim()
          : (ok ? 'Verified' : 'Verification failed');
      _snack(msg, error: !ok);
      // Verify done → pull the RC/DL details to fill the review block.
      if (ok) await _loadRcDlDetails();
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString().replaceFirst('ApiException: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  // RC Book uploaded (fresh local OR already on the server) → verify is allowed.
  bool get _rcUploaded =>
      _uploaded.containsKey('RC_BOOK') || _serverUrlFor('RC_BOOK').isNotEmpty;

  // Manual "Verify" button — the RM taps it once the RC OCR is ready, so verify
  // is never fired before the RC number is available ("RC number not found").
  // Disabled (shows "RC Verified") once rcBook.verification.rcVerified is true.
  Widget _verifyButton() {
    final verified = _rcDl?.rcVerified ?? false;
    final enabled = _rcUploaded && !_verifying && !verified;
    final color = verified ? AppColors.success : AppColors.primary;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: enabled ? _verifyRc : null,
        icon: _verifying
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2.2, color: AppColors.primary))
            : Icon(verified ? Icons.check_circle : Icons.verified_outlined,
                size: 18, color: verified ? AppColors.success : null),
        label: Text(verified
            ? 'RC Verified'
            : (_verifying ? 'Verifying…' : 'Verify RC')),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          disabledForegroundColor: verified ? AppColors.success : Colors.grey,
          minimumSize: const Size.fromHeight(48),
          side: BorderSide(
              color: verified
                  ? AppColors.success
                  : (enabled ? AppColors.primary : Colors.grey.shade400)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  // Remove an uploaded document from the server via the shared delete-document
  // API (same as the Upload/Pre-Disbursal screens); clears the row only when the
  // server confirms success.
  Future<void> _remove(String code) async {
    if (_busy.contains(code)) return;
    setState(() => _busy.add(code));
    try {
      final res =
          await _appRepo.deleteDocument(leadId: widget.lead.id, docCode: code);
      if (!mounted) return;
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
      setState(() => _uploaded.remove(code));
      _snack('${_titleFor(code)} removed');
      // Refresh so a removed server file's url/OCR clears (RC/DL rows update).
      if (code == 'RC_BOOK' || code == 'DRIVING_LICENCE') {
        await _loadRcDlDetails();
      }
    } catch (e) {
      _snack(e.toString().replaceFirst('ApiException: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(code));
    }
  }

  String _titleFor(String code) =>
      _kDocs.firstWhere((d) => d.code == code).title;

  // A doc counts as uploaded ONLY when it's on the SERVER (its RC/DL url is
  // present in rc-dl-details) — a fresh local file alone doesn't enable Submit.
  bool _docUploaded(String code) => _serverUrlFor(code).isNotEmpty;

  // All mandatory (required) docs — RC Book + Driving License — present on the
  // server → Submit is enabled.
  bool get _requiredUploaded =>
      _kDocs.where((d) => d.required).every((d) => _docUploaded(d.code));

  // Submit enables ONLY when both mandatory docs are on the server and nothing
  // is mid-upload/mid-remove.
  bool get _canSubmit => _busy.isEmpty && _requiredUploaded;

  static String _dash(String v) => v.trim().isEmpty ? '—' : v.trim();

  // ISO date → "20/02/2030". Anything else is shown as-is.
  static String _slashDate(String v) {
    final dt = DateTime.tryParse(v.trim());
    if (dt == null) return _dash(v);
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    return '$d/$m/${dt.year}';
  }

  // Final submit for the post-disbursal stage → Home on success. The uploaded
  // documents and their read-off details are already shown inline on this page.
  Future<void> _submit() async {
    if (_submitting) return;
    // RC Book + Driving License are mandatory; WCD Approval is optional.
    final missing = _kDocs
        .where((d) => d.required && !_uploaded.containsKey(d.code))
        .toList();
    if (missing.isNotEmpty) {
      _snack('Please upload ${missing.first.title} to continue.', error: true);
      return;
    }
    // Both from the disbursement-status API: applicationId (data.id) + stageId
    // (data.stages[].id). Fall back to the lead's numeric id for applicationId.
    final appId = _applicationId.trim().isNotEmpty
        ? _applicationId.trim()
        : (widget.lead.applicationId?.toString() ?? '');
    final stageId = _stageId.trim();
    if (appId.isEmpty || stageId.isEmpty) {
      _snack('Application / stage details not available.', error: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      final res = await _appRepo.postDisbursementSubmit(
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
      // Success → show a confirmation dialog, then go to the Dashboard (Home).
      await _showSubmitSuccessDialog();
      if (!mounted) return;
      Navigator.of(context)
          .pushNamedAndRemoveUntil(AppRoutes.home, (r) => false);
    } catch (e) {
      _snack(e.toString().replaceFirst('ApiException: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // Success dialog shown after the post-disbursal submit succeeds.
  Future<void> _showSubmitSuccessDialog() {
    final p = context.palette;
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.success.withValues(alpha: 0.12),
              ),
              child: const Icon(Icons.check_circle,
                  size: 44, color: AppColors.success),
            ),
            const SizedBox(height: 16),
            Text('Success',
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700, color: p.title)),
            const SizedBox(height: 8),
            Text(
              'Post-Disbursal Details submitted successfully.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.4, color: p.subtitle),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Go to Dashboard',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final rc = _rcDl?.rc;
    final dl = _rcDl?.dl;
    return AppFlowScaffold(
      title: 'Post-Disbursal Conditions',
      bottomBar: InteractionBottomBar(
        actionLabel: 'Submit',
        // Disabled (faded) until BOTH mandatory docs — RC Book and Driving
        // License — are uploaded and nothing is mid-submit.
        enabled: _canSubmit && !_submitting,
        onAction: _submit,
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            children: [
              const _InfoBanner(),
              const SizedBox(height: 16),
              FlowCard(
                heading: 'Documents to be Uploaded',
                child: Column(
                  children: [
                    for (var i = 0; i < _kDocs.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      _DocRow(
                        spec: _kDocs[i],
                        uploadedPath: _uploaded[_kDocs[i].code],
                        url: _serverUrlFor(_kDocs[i].code),
                        busy: _busy.contains(_kDocs[i].code),
                        onUpload: () => _showUploadSheet(_kDocs[i].code),
                        onRemove: () => _remove(_kDocs[i].code),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _verifyButton(),
              // Once the mandatory documents are uploaded, the "review" block —
              // the uploaded thumbnails with the details read off them — shows
              // right here on the same page (not a separate screen).
              FlowCard(
                heading: 'Uploaded Documents',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionTitle('Vehicle Details'),
                    const SizedBox(height: 12),
                    DetailRow(
                        label: 'Owner Name:',
                        labelWidth: 150,
                        value: _dash(rc?.registeredOwner ?? '')),
                    DetailRow(
                        label: 'Registration Number:',
                        labelWidth: 150,
                        value: _dash(rc?.registrationNumber ?? '')),
                    DetailRow(
                        label: 'Registration Date:',
                        labelWidth: 150,
                        value: _slashDate(rc?.registrationDate ?? '')),
                    DetailRow(
                        label: 'Chassis Number:',
                        labelWidth: 150,
                        value: _dash(rc?.chassisNumber ?? '')),
                    DetailRow(
                        label: 'Engine / Motor Serial Number:',
                        labelWidth: 150,
                        value: _dash(rc?.engineNumber ?? '')),
                    DetailRow(
                        label: 'Manufacturer :',
                        labelWidth: 150,
                        value: _dash(rc?.manufacturer ?? '')),
                    const SizedBox(height: 6),
                    Divider(color: p.fieldBorder, height: 24),
                    const _SectionTitle('Driving License'),
                    const SizedBox(height: 12),
                    DetailRow(
                        label: 'Driving License Number:',
                        labelWidth: 150,
                        value: _dash(dl?.dlNumber ?? '')),
                    DetailRow(
                        label: 'DL Expiry Date:',
                        labelWidth: 150,
                        value: _slashDate(dl?.expiryDate ?? '')),
                    DetailRow(
                        label: 'DL Issuing RTO:',
                        labelWidth: 150,
                        value: _dash(dl?.issuingRto ?? '')),
                  ],
                ),
              ),
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

/// Immutable description of one document row.
class _DocSpec {
  const _DocSpec({
    required this.code,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.required = false,
  });
  final String code;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool required; // must be uploaded before Submit (shows a red *)
}

/// Green header banner: circular badge + title + helper line.
class _InfoBanner extends StatelessWidget {
  const _InfoBanner();

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.success,
            ),
            child: const Icon(Icons.assignment_outlined,
                size: 22, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Post-Disbursal Conditions',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.success)),
                const SizedBox(height: 3),
                Text(
                  'Please upload the following documents to complete this stage.',
                  style: TextStyle(
                      fontSize: 12.5, height: 1.35, color: p.subtitle),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Vehicle Details" / "Driving License" sub-heading inside the card.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
          color: context.palette.title,
        ),
      ),
    );
  }
}

/// A tappable document preview box — shows the uploaded image (a fresh local
/// file, or a server file fetched with auth) or a fallback icon; tapping opens
/// it full-screen (image dialog / PDF viewer). Reused for both the review
/// thumbnails and the upload-row leading tiles.
class _DocPreviewBox extends StatefulWidget {
  const _DocPreviewBox({
    required this.path,
    required this.url,
    this.size = 56,
    this.fallbackIcon = Icons.description_outlined,
  });
  final String path; // fresh local file path (may be empty)
  final String url; // server file url (may be empty)
  final double size;
  final IconData fallbackIcon;

  @override
  State<_DocPreviewBox> createState() => _DocPreviewBoxState();
}

class _DocPreviewBoxState extends State<_DocPreviewBox> {
  final LeadRepository _repo = LeadRepository();
  Uint8List? _serverBytes; // fetched server image (thumbnail + view)
  bool _thumbLoading = false; // fetching the server image for the thumbnail
  bool _loading = false; // fetching a server PDF for viewing

  @override
  void initState() {
    super.initState();
    _maybeLoadServerImage();
  }

  @override
  void didUpdateWidget(covariant _DocPreviewBox old) {
    super.didUpdateWidget(old);
    // URL arrives after rc-dl-details loads → (re)fetch the server image.
    if (old.url != widget.url || old.path != widget.path) {
      _serverBytes = null;
      _maybeLoadServerImage();
    }
  }

  bool _isImageName(String p) {
    final s = p.toLowerCase();
    return s.endsWith('.jpg') || s.endsWith('.jpeg') || s.endsWith('.png');
  }

  bool get _hasLocal => widget.path.trim().isNotEmpty;
  bool get _hasUrl => widget.url.trim().startsWith('http');
  bool get _canView => _hasLocal || _hasUrl;
  bool get _urlIsImage => _isImageName(widget.url.trim());

  // Pre-fetch the server image (with auth) so the thumbnail shows the actual
  // RC/DL image, not just a doc icon. PDFs are loaded on tap instead.
  Future<void> _maybeLoadServerImage() async {
    if (_hasLocal || !_hasUrl || !_urlIsImage) return;
    setState(() => _thumbLoading = true);
    try {
      final bytes = await _repo.documentBytesFromUrl(widget.url.trim());
      if (!mounted) return;
      setState(() => _serverBytes = bytes);
    } catch (_) {
      /* keep the placeholder icon */
    } finally {
      if (mounted) setState(() => _thumbLoading = false);
    }
  }

  Future<void> _view() async {
    if (_loading) return;
    // Fresh local file — open directly.
    if (_hasLocal) {
      final path = widget.path;
      if (path.toLowerCase().endsWith('.pdf')) {
        _openPdf(path);
      } else if (File(path).existsSync()) {
        _showImage(FileImage(File(path)));
      }
      return;
    }
    // Server image already fetched for the thumbnail → show it directly.
    if (_serverBytes != null) {
      _showImage(MemoryImage(_serverBytes!));
      return;
    }
    // Server file (PDF, or image not yet fetched) — fetch (with auth) then show.
    final url = widget.url.trim();
    setState(() => _loading = true);
    try {
      final bytes = await _repo.documentBytesFromUrl(url);
      if (!mounted) return;
      if (url.toLowerCase().endsWith('.pdf')) {
        final dir = await Directory.systemTemp.createTemp('rcdl_doc');
        final f = File('${dir.path}/document.pdf');
        await f.writeAsBytes(bytes, flush: true);
        if (!mounted) return;
        _openPdf(f.path);
      } else {
        _showImage(MemoryImage(bytes));
      }
    } on ApiException catch (e) {
      if (mounted) AppToast.show(context, e.message);
    } catch (_) {
      if (mounted) AppToast.show(context, 'Could not open this document.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openPdf(String path) => Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => LeadDocPdfViewer(path: path),
      ));

  void _showImage(ImageProvider image) {
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

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = widget.size;
    final localImage = _hasLocal &&
        _isImageName(widget.path) &&
        File(widget.path).existsSync();
    final busy = _thumbLoading || _loading;
    Widget child;
    if (busy) {
      child = const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
              strokeWidth: 2.2, color: AppColors.purple));
    } else if (localImage) {
      child = Image.file(File(widget.path),
          fit: BoxFit.cover, width: s, height: s);
    } else if (_serverBytes != null) {
      child = Image.memory(_serverBytes!, fit: BoxFit.cover, width: s, height: s);
    } else {
      child = ColoredBox(
        color: AppColors.purple.withValues(alpha: 0.06),
        child: Icon(widget.fallbackIcon, size: s * 0.42, color: p.iconGrey),
      );
    }
    return GestureDetector(
      onTap: (_canView && !busy) ? _view : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: s,
        height: s,
        clipBehavior: Clip.antiAlias,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: p.fieldBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: p.fieldBorder),
        ),
        child: child,
      ),
    );
  }
}

/// Review-block thumbnail: a [_DocPreviewBox] with the document name beside it
/// (+ a "view" hint when it can be opened).
class _DocThumb extends StatelessWidget {
  const _DocThumb({required this.label, required this.path, this.url = ''});
  final String label;
  final String path;
  final String url;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final canView = path.trim().isNotEmpty || url.trim().startsWith('http');
    return Row(
      children: [
        _DocPreviewBox(path: path, url: url, size: 56),
        const SizedBox(width: 10),
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.description, size: 14, color: AppColors.purple),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: p.title),
                ),
              ),
              if (canView) ...[
                const SizedBox(width: 6),
                const Icon(Icons.visibility_outlined,
                    size: 15, color: AppColors.purple),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One document row: icon box + title/subtitle + Upload button, or (once a file
/// is picked) a thumbnail/check with a remove (✕). Disabled rows are greyed and
/// their Upload button is inert.
class _DocRow extends StatelessWidget {
  const _DocRow({
    required this.spec,
    required this.uploadedPath,
    required this.busy,
    required this.onUpload,
    required this.onRemove,
    this.url = '',
  });
  final _DocSpec spec;
  final String? uploadedPath;
  final String url; // server file url when the doc is already uploaded
  final bool busy;
  final VoidCallback onUpload;
  final VoidCallback onRemove;

  // Uploaded = a fresh local file OR an already-uploaded server file.
  bool get _uploaded => uploadedPath != null || url.trim().startsWith('http');

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final titleColor = p.title;
    final subColor = p.subtitle;

    // Leading box: once uploaded (fresh or server), a tappable preview that
    // opens the document; otherwise the doc's icon.
    final Widget leading = _uploaded
        ? _DocPreviewBox(
            path: uploadedPath ?? '',
            url: url,
            size: 40,
            fallbackIcon: spec.icon)
        : Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.purple.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(spec.icon, size: 20, color: AppColors.purple),
          );

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Mandatory docs (RC Book, Driving License) get a red " *".
                Text.rich(TextSpan(children: [
                  TextSpan(
                      text: spec.title,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: titleColor)),
                  if (spec.required)
                    const TextSpan(
                        text: ' *',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.statusRed)),
                ])),
                const SizedBox(height: 2),
                Text(spec.subtitle,
                    style: TextStyle(fontSize: 12, color: subColor)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _trailing(context),
        ],
      ),
    );
  }

  Widget _trailing(BuildContext context) {
    if (busy) {
      return const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
            strokeWidth: 2, color: AppColors.purple),
      );
    }
    if (_uploaded) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: const BoxDecoration(
                shape: BoxShape.circle, color: AppColors.success),
            child: const Icon(Icons.check, size: 16, color: Colors.white),
          ),
          // Remove — for a fresh local upload OR an already-uploaded server file
          // (deleted on the server, then the row updates).
          GestureDetector(
            onTap: onRemove,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.only(left: 6, right: 2),
              child: Icon(Icons.close, size: 18, color: AppColors.statusRed),
            ),
          ),
        ],
      );
    }
    return OutlinedButton(
      onPressed: onUpload,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        side: const BorderSide(color: AppColors.primary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: const Text('Upload',
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.primary)),
    );
  }
}
