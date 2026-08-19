import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/app_assets.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/models/lead_item.dart';
import '../../data/models/uploaded_doc.dart';
import '../../data/repositories/application_repository.dart';
import '../../data/repositories/doc_quality_repository.dart';
import '../../theme/app_colors.dart';
import '../application/application_details_screen.dart';
import '../widgets/doc_thumb.dart';
import '../widgets/interaction_ui.dart';

/// Allowed document formats and the max size enforced on every upload/capture.
const _allowedExt = ['pdf', 'png', 'jpg', 'jpeg'];
const _maxUploadBytes = 10 * 1024 * 1024; // 10 MB

/// Application sub-step 1 of 5 — Upload Documents.
/// Two tabs (Applicant / Co-Applicant), each a checklist of documents the RM
/// uploads. ID type (Aadhar/Voter) and licence type (Driving/Learning) are
/// radio-selectable. Upload is a static demo — tapping marks the doc done.
class UploadDocumentsScreen extends StatefulWidget {
  const UploadDocumentsScreen({
    super.key,
    required this.lead,
    this.stageId = '',
    this.stageType = '',
  });
  final LeadItem lead;
  final String stageId; // applicationStages[].id of the Upload Document stage
  final String stageType; // applicationStages[].stageType (e.g. "KYC")

  @override
  State<UploadDocumentsScreen> createState() => _UploadDocumentsScreenState();
}

class _UploadDocumentsScreenState extends State<UploadDocumentsScreen> {
  int _tab = 0; // 0 = Applicant, 1 = Co-Applicant
  String _appId = 'aadhar'; // aadhar | voter
  String _appLicense = 'driving'; // driving | learning
  String _coId = 'aadhar';
  // key -> the single attached file/image name (one document = one file/photo).
  final Map<String, String> _docFiles = {};
  // key -> local file path (used to preview the image thumbnail).
  final Map<String, String> _docPaths = {};
  // key -> decoded base64 THUMBNAIL bytes of a PREVIOUSLY uploaded doc (from
  // /application/details `thumbnail`). Shown when there's no fresh local file.
  final Map<String, Uint8List> _docPreviews = {};
  // key -> server THUMBNAIL url (new /application/details shape — `thumbnail`
  // sent as an http url instead of inline base64).
  final Map<String, String> _docPreviewUrls = {};
  // key -> server documentId + applicantType of a previously uploaded doc, used
  // to fetch the FULL file on demand (POST /application/document) when viewed.
  final Map<String, String> _docServerId = {};
  final Map<String, String> _docServerType = {}; // APPLICANT / CO_APPLICANT
  String? _viewingKey; // slot whose full file is being fetched for viewing
  bool _loadingExisting = true; // fetching previously-uploaded docs on open

  final DocQualityRepository _docQuality = DocQualityRepository();
  final ApplicationRepository _appRepo = ApplicationRepository();
  String? _checkingKey; // the doc row whose image is being quality-checked
  final Set<String> _serverUploading = {}; // doc rows currently uploading to the server
  final Set<String> _deleting = {}; // doc rows currently being deleted on the server
  // Keys confirmed on the server (from /application/details, or after a
  // successful upload) — used to know which sides to delete on Remove.
  final Set<String> _onServer = {};
  bool _submitting = false; // Proceed → upload-documents call in progress

  // ID front/back pair keys — these use the Capture + shared Remove/Upload UI
  // (captured images are held locally and uploaded together via the Upload btn).
  static const Set<String> _idPairKeys = {
    'app_id_front', 'app_id_back', 'co_id_front', 'co_id_back',
  };
  bool _isIdPair(String key) => _idPairKeys.contains(key);

  // "Full Aadhaar Card" slots — a single image holding BOTH sides of the
  // Aadhaar, an alternative to the front+back pair. Uploaded like PAN (single,
  // auto-uploaded) but sent to the server under the FRONT code (AADHAAR_FRONT /
  // CO_AADHAAR_FRONT). Only offered when the ID type is Aadhaar (not Voter).

  // A "Full Aadhaar" upload exists for this side (blocks the front+back rows).
  bool _fullIdPresent(bool isCo) =>
      _docFiles.containsKey(isCo ? 'co_id_full' : 'app_id_full');
  // Either front OR back has an image (blocks the Full Aadhaar row).
  bool _sideIdPresent(bool isCo) =>
      _docFiles.containsKey(isCo ? 'co_id_front' : 'app_id_front') ||
      _docFiles.containsKey(isCo ? 'co_id_back' : 'app_id_back');

  // ID documents that must pass the Digio blur / black-and-white quality check
  // before they count as uploaded (photo / bank / address proof are exempt).
  static const Set<String> _qualityKeys = {
    'app_id_front', 'app_id_back', 'app_id_full', 'app_pan', 'app_dl', 'app_ll',
    'co_id_front', 'co_id_back', 'co_id_full', 'co_pan',
  };

  bool _needsQualityCheck(String key) => _qualityKeys.contains(key);

  bool _isUploaded(String key) => _docFiles.containsKey(key);

  @override
  void initState() {
    super.initState();
    _loadExistingDocs();
  }

  // API documentCode -> this screen's slot key (reverse of [_apiFieldForKey]).
  static const Map<String, String> _apiCodeToKey = {
    'AADHAAR_FRONT': 'app_id_front', 'VOTER_ID_FRONT': 'app_id_front',
    'VOTER_ID': 'app_id_front',
    'AADHAAR_BACK': 'app_id_back', 'VOTER_ID_BACK': 'app_id_back',
    'PAN': 'app_pan',
    'DRIVING_LICENCE': 'app_dl', 'DRIVING_LICENSE': 'app_dl',
    'LEARNING_LICENCE': 'app_ll', 'LEARNING_LICENSE': 'app_ll',
    'APPLICANT_PIC': 'app_image', 'APPLICANT_IMAGE': 'app_image',
    'PASSBOOK': 'app_bank',
    'ADDRESS_PROOF': 'app_addr',
    'CO_AADHAAR_FRONT': 'co_id_front', 'CO_VOTER_ID_FRONT': 'co_id_front',
    'CO_VOTER_ID': 'co_id_front',
    'CO_AADHAAR_BACK': 'co_id_back', 'CO_VOTER_ID_BACK': 'co_id_back',
    'CO_PAN': 'co_pan',
    'CO_APPLICANT_PIC': 'co_image', 'CO_APPLICANT_IMAGE': 'co_image',
    'CO_ADDRESS_PROOF': 'co_addr',
  };

  // Fetch previously-uploaded docs and pre-fill the slots (image + name) so a
  // returning user sees what they already uploaded. Best-effort: on any error
  // the screen just shows empty slots.
  Future<void> _loadExistingDocs() async {
    try {
      final docs = await _appRepo.getDocuments(leadId: widget.lead.id);
      if (!mounted) return;
      // TEMP DEBUG: see exactly what each list contains.
      for (final d in docs.applicant) {
        debugPrint('APPLICANT doc → code=${d.documentCode} '
            'id=${d.id} thumb=${d.thumbnail.length}b mime=${d.mimeType}');
      }
      for (final d in docs.coApplicant) {
        debugPrint('CO doc → code=${d.documentCode} '
            'id=${d.id} thumb=${d.thumbnail.length}b mime=${d.mimeType}');
      }
      debugPrint('counts → applicant=${docs.applicant.length} '
          'coApplicant=${docs.coApplicant.length}');
      setState(() {
        _applyExisting(docs.applicant, 'APPLICANT');
        _applyExisting(docs.coApplicant, 'CO_APPLICANT');
        // Restore the Aadhar/Voter & Driving/Learning radios from what came back.
        if (docs.applicant.any((d) => d.documentCode.toUpperCase().contains('VOTER'))) _appId = 'voter';
        if (docs.applicant.any((d) => d.documentCode.toUpperCase().contains('LEARNING'))) _appLicense = 'learning';
        if (docs.coApplicant.any((d) => d.documentCode.toUpperCase().contains('VOTER'))) _coId = 'voter';
        _loadingExisting = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingExisting = false);
    }
  }

  // Resolve the server documentCode to a slot key. Falls back to fuzzy matching
  // when the server names Bank Passbook / Address (electricity/utility bill)
  // differently from our exact keys — otherwise their thumbnails wouldn't show.
  String? _slotKeyForCode(String code, bool isCo) {
    final c = code.toUpperCase();
    final direct = _apiCodeToKey[c];
    if (direct != null) return direct;
    if (c.contains('PASSBOOK') || c.contains('BANK')) {
      return isCo ? null : 'app_bank'; // co side has no bank slot
    }
    if (c.contains('ADDRESS') ||
        c.contains('ELECTRIC') ||
        c.contains('UTILITY') ||
        c.contains('BILL')) {
      return isCo ? 'co_addr' : 'app_addr';
    }
    return null;
  }

  void _applyExisting(List<UploadedDoc> list, String applicantType) {
    final isCo = applicantType == 'CO_APPLICANT';
    // A "Full Aadhaar" upload is stored under the FRONT code with no matching
    // BACK. So if AADHAAR_FRONT came back WITHOUT its AADHAAR_BACK, it was a Full
    // Aadhaar — route it to the Full slot instead of the front-side slot.
    final codes = list.map((d) => d.documentCode.toUpperCase()).toSet();
    final frontCode = isCo ? 'CO_AADHAAR_FRONT' : 'AADHAAR_FRONT';
    final backCode = isCo ? 'CO_AADHAAR_BACK' : 'AADHAAR_BACK';
    final frontIsFull = codes.contains(frontCode) && !codes.contains(backCode);
    final sideFrontKey = isCo ? 'co_id_front' : 'app_id_front';
    final fullKey = isCo ? 'co_id_full' : 'app_id_full';
    for (final d in list) {
      var key = _slotKeyForCode(d.documentCode, isCo);
      if (key == null) continue;
      if (frontIsFull && key == sideFrontKey) key = fullKey;
      _docFiles[key] = d.fileName.isNotEmpty ? d.fileName : d.originalName;
      _onServer.add(key); // came from the server
      // Remember the server id + side so the full file can be fetched on view.
      if (d.id.isNotEmpty) {
        _docServerId[key] = d.id;
        _docServerType[key] = applicantType;
      }
      // Small thumbnail for the list. The server sends a rendered `thumbnail`
      // (base64) for PDFs too, so use it whenever present — the full file (image
      // or PDF) still loads on tap.
      final t = d.thumbnailBytes;
      if (t != null) _docPreviews[key] = t;
      final u = d.thumbnailUrl;
      if (u.isNotEmpty) _docPreviewUrls[key] = u;
    }
  }

  String get _appIdLabel => _appId == 'aadhar' ? 'Aadhaar Card' : 'Voter ID';
  String get _coIdLabel => _coId == 'aadhar' ? 'Aadhaar Card' : 'Voter ID';

  // ID/licence type toggles: on a REAL change, drop the previously uploaded
  // image for that slot (e.g. a Driving Licence must not appear after switching
  // to Learning Licence — same `app_license` slot, different document).
  Future<void> _changeAppId(String v) async {
    if (v == _appId) return;
    await _switchIdType(
      newType: v,
      current: _appId,
      frontKey: 'app_id_front',
      backKey: 'app_id_back',
      apply: (nv) => _appId = nv,
    );
  }

  // Driving ↔ Learning licence. Same confirm-and-remove as the ID type switch:
  // if the current licence is already uploaded, ask first — Yes removes it
  // (server delete-document where on the server) then switches; No stays.
  Future<void> _changeAppLicense(String v) async {
    if (v == _appLicense) return;
    final currentKey = _appLicense == 'driving' ? 'app_dl' : 'app_ll';
    if (!_isUploaded(currentKey)) {
      setState(() => _appLicense = v);
      return;
    }
    String label(String t) =>
        t == 'driving' ? 'Driving License' : 'Learning License';
    final ok = await _confirmTypeSwitch(label(v), label(_appLicense));
    if (!ok || !mounted) return;
    final removed = await _removeSingle(currentKey);
    if (removed && mounted) setState(() => _appLicense = v);
  }

  // Remove a single doc: server delete (delete-document) when it's on the
  // server, then clear locally. Returns true on success (used by the licence
  // type switch).
  Future<bool> _removeSingle(String key) async {
    if (_deleting.contains(key)) return false;
    setState(() => _deleting.add(key));
    try {
      if (_onServer.contains(key)) {
        await _appRepo.deleteDocument(
            leadId: widget.lead.id, docCode: _apiKeyFor(key) ?? '');
      }
      if (!mounted) return false;
      setState(() {
        _docFiles.remove(key);
        _docPaths.remove(key);
        _docPreviews.remove(key);
        _docServerId.remove(key);
        _docServerType.remove(key);
        _onServer.remove(key);
      });
      return true;
    } on ApiException catch (e) {
      if (mounted) _error(e.message);
      return false;
    } catch (_) {
      if (mounted) _error('Something went wrong. Please try again.');
      return false;
    } finally {
      if (mounted) setState(() => _deleting.remove(key));
    }
  }

  Future<void> _changeCoId(String v) async {
    if (v == _coId) return;
    await _switchIdType(
      newType: v,
      current: _coId,
      frontKey: 'co_id_front',
      backKey: 'co_id_back',
      apply: (nv) => _coId = nv,
    );
  }

  // Switch the ID type (Aadhar↔Voter). If the current type already has images,
  // confirm first — Yes removes BOTH sides (server delete-document where on the
  // server) then switches; No stays. Nothing present → switch straight away.
  Future<void> _switchIdType({
    required String newType,
    required String current,
    required String frontKey,
    required String backKey,
    required void Function(String) apply,
  }) async {
    final hasAny = _isUploaded(frontKey) || _isUploaded(backKey);
    if (!hasAny) {
      setState(() => apply(newType));
      return;
    }
    String label(String t) => t == 'aadhar' ? 'Aadhaar Card' : 'Voter ID';
    final ok = await _confirmTypeSwitch(label(newType), label(current));
    if (!ok || !mounted) return;
    final removed = await _removeIdPair(frontKey, backKey);
    if (removed && mounted) setState(() => apply(newType));
  }

  // Required documents (per selection): applicant ID front+back (Aadhar OR
  // Voter — same keys), PAN, Applicant Image, Passbook, Address Proof; + the
  // SELECTED licence (Driving=app_dl OR Learning=app_ll, see _licenseKey); +
  // co-applicant ID front+back, PAN, Address Proof.
  // The ID (Aadhaar/Voter) is validated separately via [_appIdComplete] /
  // [_coIdComplete] because it can be satisfied EITHER by the front+back pair OR
  // by a single Full Aadhaar upload. These lists hold only the always-required
  // single documents.
  static const List<String> _applicantKeys = [
    'app_pan', 'app_image', 'app_bank', 'app_addr',
  ];
  static const List<String> _coApplicantKeys = [
    'co_pan', 'co_image', 'co_addr',
  ];

  // ID requirement met when EITHER a Full Aadhaar (Aadhaar type only) is on the
  // server, OR both the front and back sides are on the server.
  bool get _appIdComplete =>
      (_appId == 'aadhar' && _onServer.contains('app_id_full')) ||
      (_onServer.contains('app_id_front') && _onServer.contains('app_id_back'));
  bool get _coIdComplete =>
      (_coId == 'aadhar' && _onServer.contains('co_id_full')) ||
      (_onServer.contains('co_id_front') && _onServer.contains('co_id_back'));

  // Proceed enables ONLY when EVERY required document is actually ON THE SERVER
  // (`_onServer`) and nothing is mid-flight (no quality check / no upload). For
  // the ID pair this means the captured front+back have been Uploaded (not just
  // held locally); for the rest, their auto-upload response has succeeded.
  // NOTE: the licence (Driving / Learning — `_licenseKey`) is OPTIONAL, so it is
  // NOT required for Proceed; it's still validated/uploaded if the RM adds it.
  bool get _canProceed =>
      _checkingKey == null &&
      _serverUploading.isEmpty &&
      _appIdComplete &&
      _coIdComplete &&
      _applicantKeys.every(_onServer.contains) &&
      _coApplicantKeys.every(_onServer.contains);

  // Proceed → documents are already uploaded per-document (POST
  // /application/upload). This call (POST /application/upload-documents) just
  // submits the stage data — leadId + stageId + stageType + status, NO files —
  // then advances to the next step.
  Future<void> _submitDocuments() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final res = await _appRepo.uploadDocuments(
        leadId: widget.lead.id,
        stageId: widget.stageId,
        stageType: widget.stageType,
        status: 'draft',
        filePaths: const {}, // files already sent per-document
      );
      if (!mounted) return;
      // Backend returns { success: true, message, data }. (Accept `status` too
      // in case another endpoint shape is used.)
      final ok = res is Map && (res['success'] == true || res['status'] == true);
      final msg = (res is Map &&
              res['message'] is String &&
              (res['message'] as String).trim().isNotEmpty)
          ? (res['message'] as String).trim()
          : (ok ? 'Documents submitted' : 'Could not submit documents');
      AppToast.show(context, msg,
          type: ok ? ToastType.success : ToastType.error);
      // Only advance to the Application Details flow when status == true.
      if (!ok) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ApplicationDetailsScreen(
            lead: widget.lead,
            stageId: widget.stageId,
            stageType: widget.stageType,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) _error(e.message);
    } catch (_) {
      if (mounted) _error('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // Tapping Upload opens a sheet: pick a file (PDF/image) OR capture from camera.
  Future<void> _showUploadSheet(String key) async {
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
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == 'file') {
      await _pickFile(key);
    } else if (choice == 'camera') {
      await _capturePhoto(key);
    }
  }

  // Pick a single PDF/image file (png/jpg/jpeg). PDFs are size-checked here;
  // images are cropped first and the 10 MB cap is enforced on the result.
  Future<void> _pickFile(String key) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _allowedExt,
        allowMultiple: false, // single selection only
      ); 
      if (result == null || result.files.isEmpty) return; // user cancelled
      final f = result.files.first;
      final ext = (f.extension ?? '').toLowerCase();
      if (!_allowedExt.contains(ext)) {
        _error('Sirf PDF ya image (png/jpg/jpeg) upload ho sakti hai');
        return;
      }
      if (f.path == null) {
        _error('File select nahi hui, dobara try karein');
        return;
      }
      // PDF has no crop step → enforce the 10 MB cap right away.
      if (ext == 'pdf' && f.size > _maxUploadBytes) {
        _error('Please upload PDF 10 MB or below');
        return;
      }
      await _onPicked(key, f.path!, f.name, ext);
    } catch (_) {
      _error('File select nahi hui, dobara try karein');
    }
  }

  // Capture a single image from the camera — full quality, no compression /
  // resizing. The 10 MB cap is enforced on the final cropped image in _onPicked.
  Future<void> _capturePhoto(String key) async {
    try {
      final XFile? img =
          await ImagePicker().pickImage(source: ImageSource.camera);
      if (img == null) return; // cancelled
      final ext = img.name.contains('.')
          ? img.name.split('.').last.toLowerCase()
          : 'jpg';
      await _onPicked(key, img.path, img.name, ext);
    } catch (_) {
      _error('Camera nahi khula, dobara try karein');
    }
  }

  /// After a file/photo is picked: images get a free/manual crop step first (so
  /// a full Aadhar photo can be cropped to the card). For ID documents the
  /// cropped image then runs the Digio check + slot match. On any failure show a
  /// dialog and do NOT mark the row uploaded. PDFs skip crop and the check.
  Future<void> _onPicked(String key, String path, String name, String ext) async {
    final isImage = ext == 'png' || ext == 'jpg' || ext == 'jpeg';
    var usePath = path;
    var useName = name;

    if (isImage) {
      final cropped = await _cropImage(path);
      if (cropped == null) return; // user cancelled the crop → nothing uploaded
      usePath = cropped;
      useName = cropped.split(Platform.pathSeparator).last;
      // Enforce the 10 MB cap on the final cropped image.
      final size = await File(cropped).length();
      if (size > _maxUploadBytes) {
        _error('Please upload image 10 MB or below');
        return;
      }
      if (!mounted) return;
    }

    if (_needsQualityCheck(key) && isImage) {
      final expType = _expectedIdType(key); // AADHAAR / VOTER_ID / PAN / DRIVING_LICENSE
      final expPart = _expectedPart(key); // FRONT / BACK
      setState(() => _checkingKey = key);
      try {
        final result = await _docQuality.analyzeIdCard(
          filePath: usePath,
          expectedIds: [expType],
          fileName: useName,
        );
        if (!mounted) return;
        // 1) Image quality first — is it blurred / black-and-white?
        if (!result.qualityPassed) {
          _showDocErrorDialog(
            'Poor Image Quality',
            '${_docLabelForKey(key)} image is not in good quality. '
                'Please upload a proper image.',
          );
          return;
        }
        // 2) Then the document type (e.g. PAN uploaded in an Aadhar slot).
        if (result.detectedIdType != expType) {
          _showDocErrorDialog(
            'Wrong Document',
            _wrongTypeMessage(key, result.detectedIdType),
          );
          return;
        }
        // 3) Then the side. For the Full Aadhaar slot the image must contain
        // BOTH sides; for front/back slots it must be that exact side. Only
        // enforced when the API actually reported a part.
        if (result.detectedPart.isNotEmpty && result.detectedPart != expPart) {
          if (expPart == 'BOTH') {
            _showDocErrorDialog(
              'Incomplete Aadhaar',
              'Please upload the complete Aadhaar card showing both front and '
                  'back in a single image.',
            );
          } else {
            _showDocErrorDialog(
              'Wrong Side',
              'Please upload the ${expPart == 'BACK' ? 'back' : 'front'} side of '
                  '${_docLabelForKey(key)}.',
            );
          }
          return;
        }
        // 4) Document verification (authenticity) — DISABLED for now.
        // if (!result.verified) {
        //   _showDocErrorDialog(
        //     'Verification Failed',
        //     '${_docLabelForKey(key)} could not be verified. Please upload a '
        //         'clear, valid image.',
        //   );
        //   return;
        // }
      } on ApiException catch (e) {
        if (!mounted) return;
        _error(e.message);
        return;
      } finally {
        if (mounted) setState(() => _checkingKey = null);
      }
    }
    if (!mounted) return;
    setState(() {
      _docFiles[key] = useName; // one file per document
      _docPaths[key] = usePath;
    });
    // ID front/back pair → HOLD locally; the shared Upload button sends both.
    // Every other doc uploads to the server right away.
    if (!_isIdPair(key)) {
      await _uploadToServer(key);
    }
  }

  // --- Per-document upload (POST /application/upload) ---------------------------
  // Front/back pairs: a side's partner key. Single docs are not in this map.
  static const Map<String, String> _pairPartner = {
    'app_id_front': 'app_id_back',
    'app_id_back': 'app_id_front',
    'co_id_front': 'co_id_back',
    'co_id_back': 'co_id_front',
  };

  // screen key -> API field name (resolves Aadhar/Voter, Driving/Learning).
  String? _apiKeyFor(String key) {
    switch (key) {
      case 'app_id_front':
        return _appId == 'aadhar' ? 'AADHAAR_FRONT' : 'VOTER_ID_FRONT';
      case 'app_id_back':
        return _appId == 'aadhar' ? 'AADHAAR_BACK' : 'VOTER_ID_BACK';
      case 'co_id_front':
        return _coId == 'aadhar' ? 'CO_AADHAAR_FRONT' : 'CO_VOTER_ID_FRONT';
      case 'co_id_back':
        return _coId == 'aadhar' ? 'CO_AADHAAR_BACK' : 'CO_VOTER_ID_BACK';
      // Full Aadhaar (both sides in one image) → stored under the FRONT code.
      case 'app_id_full':
        return 'AADHAAR_FRONT';
      case 'co_id_full':
        return 'CO_AADHAAR_FRONT';
      case 'app_pan':
        return 'PAN';
      case 'app_dl':
        return 'DRIVING_LICENCE';
      case 'app_ll':
        return 'LEARNING_LICENCE';
      case 'app_image':
        return 'APPLICANT_PIC';
      case 'app_bank':
        return 'PASSBOOK';
      case 'app_addr':
        return 'ADDRESS_PROOF';
      case 'co_pan':
        return 'CO_PAN';
      case 'co_image':
        return 'CO_APPLICANT_PIC';
      case 'co_addr':
        return 'CO_ADDRESS_PROOF';
    }
    return null;
  }

  // A side is "present" if it has a fresh local file OR is already uploaded
  // (e.g. the partner is on the server from a previous session).
  bool _present(String key) => _docPaths[key] != null || _docFiles.containsKey(key);

  // Upload [justAdded] to the server. For a front/back pair we proceed once BOTH
  // sides are PRESENT; we send ONLY the side(s) that have a fresh local file.
  // Until the pair is complete the just-added side gets a LOCAL "Upload
  // Successful"; when the server call runs, the SERVER's message is shown.
  Future<void> _uploadToServer(String justAdded) async {
    final partner = _pairPartner[justAdded];
    final List<String> callKeys;
    if (partner != null) {
      final front = justAdded.endsWith('_front') ? justAdded : partner;
      final back = justAdded.endsWith('_back') ? justAdded : partner;
      // Partner not there yet → this side is accepted (Digio passed, thumbnail
      // shown); show a local success and wait for the other side.
      if (!_present(partner)) {
        _toast('Upload Successful', ok: true);
        return;
      }
      // Send only the side(s) with a fresh local file.
      callKeys = [front, back].where((k) => _docPaths[k] != null).toList();
    } else {
      callKeys = [justAdded];
    }

    final files = <String, String>{};
    for (final k in callKeys) {
      final api = _apiKeyFor(k);
      final p = _docPaths[k];
      if (api != null && p != null) files[api] = p;
    }
    if (files.isEmpty) return;

    // Loader only on the image being uploaded right now (the just-added one),
    // not its already-uploaded partner.
    setState(() => _serverUploading.add(justAdded));
    try {
      final res = await _appRepo.uploadFiles(leadId: widget.lead.id, files: files);
      if (!mounted) return;
      final ok = res is Map && (res['success'] == true || res['status'] == true);
      final msg = (res is Map &&
              res['message'] is String &&
              (res['message'] as String).trim().isNotEmpty)
          ? (res['message'] as String).trim()
          : (ok ? 'Document uploaded' : 'Upload failed');
      print("ye msg");
      print(res['message']);
      if (ok) {
        _onServer.addAll(callKeys); // now on the server (so Remove can delete)
        _toast(msg, ok: true); // show the SERVER message
      } else {
        _handleUploadError(ApiException(msg), callKeys);
      }
    } on ApiException catch (e) {
      if (mounted) _handleUploadError(e, callKeys);
    } catch (_) {
      if (mounted) {
        _handleUploadError(
          ApiException('Something went wrong. Please try again.'),
          callKeys,
        );
      }
    } finally {
      if (mounted) setState(() => _serverUploading.remove(justAdded));
    }
  }

  // Green/red toast helper.
  void _toast(String msg, {required bool ok}) {
    AppToast.show(context, msg,
        type: ok ? ToastType.success : ToastType.error);
  }


  // On upload failure, remove the failed image(s) so the user re-uploads. If the
  // server names a specific field (e.g. AADHAAR_BACK) we drop ONLY that side;
  // otherwise (generic error) we drop all images in this call (both for a pair).
  void _handleUploadError(ApiException e, List<String> callKeys) {
    List<String> toRemove = callKeys;
    if (callKeys.length > 1) {
      final blob = '${e.message} ${e.data ?? ''}'.toUpperCase();
      final named = callKeys.where((k) {
        final api = _apiKeyFor(k);
        return api != null && blob.contains(api);
      }).toList();
      if (named.length == 1) toRemove = named; // exactly one side identified
    }
    setState(() {
      for (final k in toRemove) {
        _docFiles.remove(k);
        _docPaths.remove(k);
      }
    });
    _showDocErrorDialog('Upload Failed', e.message);
  }

  /// Open a free/manual cropper for [path] (no fixed aspect ratio — the user
  /// drags the crop box freely and can pick a ratio preset). Returns the cropped
  /// file path, or null if the user cancelled.
  Future<String?> _cropImage(String path) async {
    final cropped = await ImageCropper().cropImage(
      sourcePath: path,
      // No `aspectRatio` → free-form crop.
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 100, // max quality — no visible compression / no resize
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Image',
          toolbarColor: AppColors.deepOrange,
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: AppColors.purple,
          lockAspectRatio: false, // manual: user can resize freely
          hideBottomControls: false, // show ratio + rotate controls
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
          aspectRatioLockEnabled: false, // manual crop
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

  // Digio id_type the slot expects (follows the selected Aadhar/Voter type).
  // Driving & Learning licences both detect as DRIVING_LICENSE.
  String _expectedIdType(String key) {
    switch (key) {
      case 'app_id_front':
      case 'app_id_back':
        return _appId == 'aadhar' ? 'AADHAAR' : 'VOTER_ID';
      case 'co_id_front':
      case 'co_id_back':
        return _coId == 'aadhar' ? 'AADHAAR' : 'VOTER_ID';
      case 'app_id_full':
      case 'co_id_full':
        return 'AADHAAR';
      case 'app_pan':
      case 'co_pan':
        return 'PAN';
      case 'app_dl':
      case 'app_ll':
        return 'DRIVING_LICENSE';
      default:
        return '';
    }
  }

  // Expected side. PAN & licence are single-sided → FRONT. The Full Aadhaar slot
  // must show BOTH sides in one image → BOTH.
  String _expectedPart(String key) {
    switch (key) {
      case 'app_id_back':
      case 'co_id_back':
        return 'BACK';
      case 'app_id_full':
      case 'co_id_full':
        return 'BOTH';
      default:
        return 'FRONT';
    }
  }

  // Human label for the document at [key] (follows the selected ID/licence type).
  String _docLabelForKey(String key) {
    switch (key) {
      case 'app_id_front':
      case 'app_id_back':
        return _appIdLabel;
      case 'co_id_front':
      case 'co_id_back':
        return _coIdLabel;
      case 'app_id_full':
      case 'co_id_full':
        return 'Aadhaar Card';
      case 'app_pan':
      case 'co_pan':
        return 'PAN Card';
      case 'app_dl':
        return 'Driving License';
      case 'app_ll':
        return 'Learning License';
      default:
        return 'Document';
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

  String _wrongTypeMessage(String key, String detected) {
    final expected = _docLabelForKey(key);
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
        content: Text(
          message,
          style: TextStyle(fontSize: 14, color: p.subtitle, height: 1.4),
        ),
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

  // Tap a thumbnail → view the image full-size in a dialog with a close button.
  void _showImagePreview(String path) {
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
                child: Image.file(File(path), fit: BoxFit.contain),
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
                    shape: BoxShape.circle,
                    color: Colors.black54,
                  ),
                  child: const Icon(Icons.close, size: 20, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Tap a previously-uploaded (server, base64) image → view it full-size.
  void _showMemoryPreview(Uint8List bytes) {
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
                    shape: BoxShape.circle,
                    color: Colors.black54,
                  ),
                  child: const Icon(Icons.close, size: 20, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Tap a PDF → view it full-screen (modal page) with a close button.
  void _showPdfPreview(String path) {
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _PdfViewerScreen(path: path),
    ));
  }

  // View a PREVIOUSLY-uploaded (server) document. The details list only carries
  // a small thumbnail now, so the full file is fetched on demand via
  // POST /application/document (documentId + applicantType), then shown — image
  // in the in-app viewer, PDF written to a temp file and opened full-screen.
  Future<void> _viewServerDoc(String key) async {
    if (_viewingKey != null) return; // one fetch at a time
    final id = _docServerId[key];
    final type = _docServerType[key];
    if (id == null || id.isEmpty || type == null) return;
    setState(() => _viewingKey = key);
    try {
      final file =
          await _appRepo.getDocumentFile(documentId: id, applicantType: type);
      if (!mounted) return;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        _error('Document could not be loaded. Please try again.');
        return;
      }
      if (file.isPdf) {
        await _showPdfBytes(bytes);
      } else {
        _showMemoryPreview(bytes);
      }
    } on ApiException catch (e) {
      if (mounted) _error(e.message);
    } catch (_) {
      if (mounted) _error('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _viewingKey = null);
    }
  }

  // Write fetched PDF bytes to a temp file and open the full-screen viewer
  // (flutter_pdfview needs a file path).
  Future<void> _showPdfBytes(Uint8List bytes) async {
    try {
      final dir = await Directory.systemTemp.createTemp('doc_view');
      final f = File('${dir.path}/document.pdf');
      await f.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      _showPdfPreview(f.path);
    } catch (_) {
      if (mounted) _error('Could not open this PDF.');
    }
  }

  // Remove (X): delete ONLY this side/document on the server, then clear it
  // locally. The per-file code (AADHAAR_FRONT / AADHAAR_BACK / VOTER_ID_FRONT …,
  // from [_apiKeyFor]) deletes just that one — front X removes front, back X
  // removes back.
  Future<void> _removeFile(String key) async {
    if (_deleting.contains(key)) return;
    final docCode = _apiKeyFor(key) ?? '';
    setState(() => _deleting.add(key));
    try {
      final res =
          await _appRepo.deleteDocument(leadId: widget.lead.id, docCode: docCode);
      if (!mounted) return;
      final ok = res is Map && (res['success'] == true || res['status'] == true);
      if (!ok) {
        final msg = (res is Map &&
                res['message'] is String &&
                (res['message'] as String).trim().isNotEmpty)
            ? (res['message'] as String).trim()
            : 'Could not delete document';
        _error(msg);
        return;
      }
      setState(() {
        _docFiles.remove(key);
        _docPaths.remove(key);
        _docPreviews.remove(key);
        _docServerId.remove(key);
        _docServerType.remove(key);
        _onServer.remove(key);
      });
    } on ApiException catch (e) {
      if (mounted) _error(e.message);
    } catch (_) {
      if (mounted) _error('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _deleting.remove(key));
    }
  }

  // Shared Remove for the ID pair: removes BOTH sides. Whatever is on the server
  // is deleted (delete-document, same logic), and both local images are cleared.
  // Returns true if the removal completed (used by the radio-switch confirm).
  Future<bool> _removeIdPair(String frontKey, String backKey) async {
    if (_deleting.contains(frontKey) || _deleting.contains(backKey)) return false;
    setState(() {
      _deleting.add(frontKey);
      _deleting.add(backKey);
    });
    try {
      for (final k in [frontKey, backKey]) {
        if (_onServer.contains(k)) {
          await _appRepo.deleteDocument(
              leadId: widget.lead.id, docCode: _apiKeyFor(k) ?? '');
        }
      }
      if (!mounted) return false;
      setState(() {
        for (final k in [frontKey, backKey]) {
          _docFiles.remove(k);
          _docPaths.remove(k);
          _docPreviews.remove(k);
          _docServerId.remove(k);
          _docServerType.remove(k);
          _onServer.remove(k);
        }
      });
      return true;
    } on ApiException catch (e) {
      if (mounted) _error(e.message);
      return false;
    } catch (_) {
      if (mounted) _error('Something went wrong. Please try again.');
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _deleting.remove(frontKey);
          _deleting.remove(backKey);
        });
      }
    }
  }

  // Confirm dialog shown before switching the ID type when images already exist.
  Future<bool> _confirmTypeSwitch(String newType, String currentType) async {
    final p = context.palette;
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Change document type?',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: p.title)),
        content: Text(
          'If you select $newType, your uploaded $currentType will be removed.',
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
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Yes',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  void _error(String msg) {
    AppToast.show(context, msg, type: ToastType.error);
  }


  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PopScope(
      // Back is always allowed — even while the details API is still loading.
      // Popping unmounts the screen; the in-flight response is ignored via the
      // `mounted` guard in _loadExistingDocs, so the loader just disappears.
      canPop: true,
      child: Scaffold(
      backgroundColor: p.surface,
      appBar: AppBar(
        backgroundColor: p.cardBg,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, size: 20, color: p.title),
          // Enabled even while loading — back pops the page & dismisses the loader.
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text('Upload Documents',
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700, color: p.title)),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  children: [
                    Center(
                      child: Text('Step 1 of 5',
                          style: TextStyle(fontSize: 13, color: p.subtitle)),
                    ),
                    const SizedBox(height: 12),
                    _maxSizeNote(),
                    const SizedBox(height: 12),
                    _tabs(),
                    const SizedBox(height: 14),
                    _tab == 0 ? _applicantCard() : _coApplicantCard(),
                  ],
                ),
              ),
              InteractionBottomBar(
                actionLabel: _submitting ? 'Uploading…' : 'Proceed',
                enabled: _canProceed && !_submitting,
                onAction: _submitDocuments,
              ),
            ],
          ),
          // Full-screen loader while previously-uploaded docs are fetched. The
          // AbsorbPointer blocks all taps; it stays until the API responds.
          if (_loadingExisting)
            const Positioned.fill(
              child: AbsorbPointer(
                child: ColoredBox(
                  color: Color(0x66000000), // light transparent black
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.purple),
                  ),
                ),
              ),
            ),
        ],
      ),
      ),
    );
  }

  // ---- Segmented tabs ----
  // A single "max 10 MB" note that applies to every document upload.
  Widget _maxSizeNote() {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.purple.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: AppColors.purple),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Max 10 MB per document — single image or PDF.',
              style: TextStyle(fontSize: 12, color: p.subtitle),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabs() {
    final p = context.palette;
    Widget seg(String label, int i) {
      final active = _tab == i;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _tab = i),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? AppColors.purple : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: active ? Colors.white : p.subtitle)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: p.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.fieldBorder),
      ),
      child: Row(children: [
        seg('Applicant Documents', 0),
        seg('Co-Applicant Documents', 1),
      ]),
    );
  }

  // ---- Applicant ----
  Widget _applicantCard() {
    final p = context.palette;
    return InteractionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Applicant Documents',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: p.title)),
          const SizedBox(height: 12),
          _group([
            _radioPair('Aadhaar Card', 'aadhar', 'Voter ID', 'voter', _appId,
                _changeAppId),
            _idCaptureRow('app_id_front', '$_appIdLabel (Front side)',
                disabled: _fullIdPresent(false)),
            _divider(),
            _idCaptureRow('app_id_back', '$_appIdLabel (Back side)',
                disabled: _fullIdPresent(false)),
            _idActionRow('app_id_front', 'app_id_back',
                disabled: _fullIdPresent(false)),
            // Full Aadhaar Card — a single image with BOTH sides, an alternative
            // to front+back (Aadhaar only, not Voter). Disabled while front/back
            // is in use so only ONE path is followed.
            if (_appId == 'aadhar') ...[
              _orSeparator(),
              _docRow('app_id_full', AppAssets.document, 'Full Aadhaar Card',
                  sub: '(Both sides in one image)',
                  disabled: _sideIdPresent(false)),
            ],
          ]),
          const SizedBox(height: 12),
          _group([_docRow('app_pan', AppAssets.document, 'PAN Card')]),
          const SizedBox(height: 12),
          _group([
            _radioPair('Driving License', 'driving', 'Learning License',
                'learning', _appLicense, _changeAppLicense),
            // Separate field per type: Driving shows app_dl, Learning shows
            // app_ll — each keeps its own image when you switch back and forth.
            if (_appLicense == 'driving')
              _docRow('app_dl', AppAssets.document, 'Driving License',
                  required: false)
            else
              _docRow('app_ll', AppAssets.document, 'Learning License',
                  required: false),
          ]),
          const SizedBox(height: 12),
          _group([
            _docRowIcon('app_image', Icons.person_outline, 'Applicant Image')
          ]), 
          const SizedBox(height: 12),
          _group([_docRow('app_bank', AppAssets.document, 'Bank Passbook')]),
          const SizedBox(height: 12),
          _group([
            _docRowIcon('app_addr', Icons.location_on_outlined,
                'Permanent Address Proof',
                sub: '(Electricity/Gas/Water Bill/Property Tax)')
          ]),
        ],
      ),
    );
  }

  // ---- Co-Applicant ----
  Widget _coApplicantCard() {
    final p = context.palette;
    return InteractionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Co-Applicant Documents',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: p.title)),
          const SizedBox(height: 12),
          _group([
            _radioPair('Aadhaar Card', 'aadhar', 'Voter ID', 'voter', _coId,
                _changeCoId),
            _idCaptureRow('co_id_front', '$_coIdLabel (Front side)',
                disabled: _fullIdPresent(true)),
            _divider(),
            _idCaptureRow('co_id_back', '$_coIdLabel (Back side)',
                disabled: _fullIdPresent(true)),
            _idActionRow('co_id_front', 'co_id_back',
                disabled: _fullIdPresent(true)),
            // Full Aadhaar Card — single image with BOTH sides (Aadhaar only).
            if (_coId == 'aadhar') ...[
              _orSeparator(),
              _docRow('co_id_full', AppAssets.document, 'Full Aadhaar Card',
                  sub: '(Both sides in one image)',
                  disabled: _sideIdPresent(true)),
            ],
          ]),
          const SizedBox(height: 12),
          _group([_docRow('co_pan', AppAssets.document, 'PAN Card')]),
          const SizedBox(height: 12),
          _group([
            _docRowIcon('co_image', Icons.person_outline, 'Co-Applicant Image')
          ]),
          const SizedBox(height: 12),
          _group([
            _docRowIcon('co_addr', Icons.location_on_outlined,
                'Permanent Address Proof',
                sub: '(Electricity/Gas/Water Bill/Property Tax)')
          ]),
        ],
      ),
    );
  }

  // ---- Pieces ----
  Widget _group(List<Widget> children) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.fieldBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _divider() {
    final p = context.palette;
    return Divider(height: 1, color: p.fieldBorder);
  }

  Widget _radioPair(String l1, String v1, String l2, String v2, String value,
      ValueChanged<String> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          _radio(l1, value == v1, () => onChanged(v1)),
          const SizedBox(width: 24),
          _radio(l2, value == v2, () => onChanged(v2)),
        ],
      ),
    );
  }

  Widget _radio(String label, bool selected, VoidCallback onTap) {
    final p = context.palette;
    return GestureDetector(
      onTap: onTap,
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
                  width: selected ? 5 : 1.5),
            ),
          ),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 13.5, color: p.title)),
        ],
      ),
    );
  }

  // 36×36 purple-tinted rounded thumbnail box wrapping [child] (placeholder
  // icon or a small loader).
  Widget _thumbBox(Widget child) {
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.purple.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(9),
      ),
      child: child,
    );
  }

  // ---- ID front/back pair (Capture per side + shared Remove/Upload) ----
  // [disabled] dims the row and blocks Capture (used when a Full Aadhaar upload
  // is present, so the front/back path is not usable at the same time).
  Widget _idCaptureRow(String key, String title, {bool disabled = false}) {
    final p = context.palette;
    final uploaded = _docFiles[key] != null;
    // Row loader only during the Digio capture check — the server upload/delete
    // loaders live on the shared Upload/Remove buttons, not on the side rows.
    final busy = _checkingKey == key;
    final path = _docPaths[key];
    final isImagePath = path != null && !path.toLowerCase().endsWith('.pdf');
    final isPdfPath = path != null && path.toLowerCase().endsWith('.pdf');
    final serverImg = path == null ? _docPreviews[key] : null;
    final serverUrl = path == null ? (_docPreviewUrls[key] ?? '') : '';

    final viewing = _viewingKey == key; // fetching the full file to view
    Widget thumb;
    if (viewing) {
      thumb = _thumbBox(
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
              strokeWidth: 2.2, color: AppColors.purple),
        ),
      );
    } else if (uploaded && isImagePath) {
      thumb = GestureDetector(
        onTap: () => _showImagePreview(path),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: Image.file(File(path), width: 36, height: 36, fit: BoxFit.cover),
        ),
      );
    } else if (uploaded && (serverImg != null || serverUrl.isNotEmpty)) {
      thumb = GestureDetector(
        onTap: () => _viewServerDoc(key),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: DocThumbImage(
              url: serverUrl,
              bytes: serverImg,
              width: 36,
              height: 36,
              fit: BoxFit.cover,
              placeholder: _thumbBox(AppIcon(AppAssets.document,
                  size: 20, color: AppColors.purple))),
        ),
      );
    } else if (uploaded && isPdfPath) {
      thumb = GestureDetector(
        onTap: () => _showPdfPreview(path),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.statusRed.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Icon(Icons.picture_as_pdf,
              size: 20, color: AppColors.statusRed),
        ),
      );
    } else if (uploaded && _docServerId[key] != null) {
      // On the server but no inline thumbnail (e.g. a PDF) — tap to load & view.
      thumb = GestureDetector(
        onTap: () => _viewServerDoc(key),
        child:
            _thumbBox(AppIcon(AppAssets.document, size: 20, color: AppColors.purple)),
      );
    } else {
      thumb = _thumbBox(
          AppIcon(AppAssets.document, size: 20, color: AppColors.purple));
    }

    return Opacity(
      opacity: disabled ? 0.4 : 1,
      child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          thumb,
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(
                  text: title,
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, color: p.title)),
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
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                  strokeWidth: 2.4, color: AppColors.purple),
            )
          else if (uploaded)
            const Icon(Icons.check_circle, size: 22, color: AppColors.success)
          else
            OutlinedButton.icon(
              onPressed: disabled ? null : () => _showUploadSheet(key),
              icon: const Icon(Icons.camera_alt_outlined, size: 16),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.purple,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: Size.zero,
                side: const BorderSide(color: AppColors.purple),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              label: const Text('Capture',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
      ),
    );
  }

  // Shared Remove + Upload for the ID pair (below the two capture rows).
  // [disabled] blocks both buttons (used when a Full Aadhaar upload is present).
  Widget _idActionRow(String frontKey, String backKey, {bool disabled = false}) {
    final bothPresent = _isUploaded(frontKey) && _isUploaded(backKey);
    final uploading = _serverUploading.contains(frontKey) ||
        _serverUploading.contains(backKey);
    final deleting =
        _deleting.contains(frontKey) || _deleting.contains(backKey);
    final busy = uploading || deleting;
    // Already on the server? (nothing fresh to upload)
    final bothOnServer =
        _onServer.contains(frontKey) && _onServer.contains(backKey);
    final canUpload = bothPresent && !busy && !bothOnServer && !disabled;
    final canRemove = bothPresent && !busy && !disabled;

    return Opacity(
      opacity: disabled ? 0.4 : 1,
      child: Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: canRemove ? () => _removeIdPair(frontKey, backKey) : null,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 11),
                side: BorderSide(
                    color: canRemove ? AppColors.statusRed : Colors.grey.shade400),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: deleting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: AppColors.statusRed))
                  : Text('Remove',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: canRemove
                              ? AppColors.statusRed
                              : Colors.grey)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Opacity(
              opacity: canUpload ? 1 : 0.5,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppColors.buttonGradient,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ElevatedButton(
                  onPressed: canUpload ? () => _uploadToServer(frontKey) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    disabledBackgroundColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: uploading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.2, color: Colors.white))
                      : Text(bothOnServer ? 'Uploaded' : 'Upload',
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                ),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _docRow(String key, String svg, String title,
          {String? sub, bool required = true, bool disabled = false}) =>
      _docRowBase(key, AppIcon(svg, size: 20, color: AppColors.purple), title,
          sub, required, disabled);

  Widget _docRowIcon(String key, IconData icon, String title,
          {String? sub, bool required = true}) =>
      _docRowBase(key, Icon(icon, size: 20, color: AppColors.purple), title,
          sub, required, false);

  // [disabled] dims the row and blocks Upload — used for the Full Aadhaar row
  // when the front/back path is already in use.
  Widget _docRowBase(String key, Widget icon, String title, String? sub,
      bool required, bool disabled) {
    final p = context.palette;
    final name = _docFiles[key];
    final uploaded = name != null;
    // Spinner shows during BOTH the Digio quality check and the server upload.
    final checking = _checkingKey == key ||
        _serverUploading.contains(key) ||
        _deleting.contains(key);
    final path = _docPaths[key];
    final isImagePath = path != null && !path.toLowerCase().endsWith('.pdf');
    final isPdfPath = path != null && path.toLowerCase().endsWith('.pdf');
    // Previously-uploaded server image (base64) — shown when there's no fresh
    // local file for this slot.
    final serverImg = path == null ? _docPreviews[key] : null;
    final serverUrl = path == null ? (_docPreviewUrls[key] ?? '') : '';
    return Opacity(
      opacity: disabled ? 0.4 : 1,
      child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          if (_viewingKey == key)
            // Fetching the full file to view.
            _thumbBox(
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2.2, color: AppColors.purple),
              ),
            )
          else if (uploaded && isImagePath)
            GestureDetector(
              onTap: () => _showImagePreview(path),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Image.file(File(path),
                    width: 36, height: 36, fit: BoxFit.cover),
              ),
            )
          else if (uploaded && (serverImg != null || serverUrl.isNotEmpty))
            GestureDetector(
              onTap: () => _viewServerDoc(key),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: DocThumbImage(
                    url: serverUrl,
                    bytes: serverImg,
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                    placeholder: _thumbBox(AppIcon(AppAssets.document,
                        size: 20, color: AppColors.purple))),
              ),
            )
          else if (uploaded && isPdfPath)
            // PDF → tap to view it full-screen, like the image preview.
            GestureDetector(
              onTap: () => _showPdfPreview(path),
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.statusRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.picture_as_pdf,
                    size: 20, color: AppColors.statusRed),
              ),
            )
          else if (uploaded && _docServerId[key] != null)
            // On the server but no inline thumbnail — tap to load & view.
            GestureDetector(
              onTap: () => _viewServerDoc(key),
              child: _thumbBox(icon),
            )
          else
            _thumbBox(icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(TextSpan(children: [
                  TextSpan(
                      text: title,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: p.title)),
                  if (required)
                    const TextSpan(
                        text: ' *',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.statusRed)),
                  if (sub != null)
                    TextSpan(
                        text: '  $sub',
                        style: TextStyle(fontSize: 11, color: p.subtitle)),
                ])),
                // File name shows only AFTER the loader (Digio check + upload)
                // completes — not while it's still in progress.
                if (uploaded && !checking) ...[
                  const SizedBox(height: 2),
                  Text(name,
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
          if (checking)
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
              onTap: () => _removeFile(key),
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
            OutlinedButton(
              onPressed: disabled ? null : () => _showUploadSheet(key),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                minimumSize: Size.zero,
                side: const BorderSide(color: AppColors.statusRed),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Upload',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.statusRed)),
            ),
        ],
      ),
      ),
    );
  }

  // A small "OR" divider shown between the front+back rows and the Full Aadhaar
  // option, signalling the two are alternatives.
  Widget _orSeparator() {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Divider(height: 1, color: p.fieldBorder)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text('OR',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: p.subtitle)),
          ),
          Expanded(child: Divider(height: 1, color: p.fieldBorder)),
        ],
      ),
    );
  }
}

/// Full-screen PDF viewer (opened from a tapped PDF document row).
class _PdfViewerScreen extends StatefulWidget {
  const _PdfViewerScreen({required this.path});
  final String path;

  @override
  State<_PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<_PdfViewerScreen> {
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
              onRender: (_) {},
            ),
    );
  }
}
