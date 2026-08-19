import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/app_assets.dart';
import '../../data/models/financial_approval.dart';
import '../../data/models/lead_item.dart';
import '../../data/repositories/application_repository.dart';
import '../../data/repositories/lead_repository.dart';
import '../../data/services/send_location_channel.dart';
import '../../theme/app_colors.dart';
import '../widgets/interaction_ui.dart';
import 'application_flow_ui.dart';
import 'esign_pending_screen.dart';

/// Field Investigation (FI) — the RM captures their live location at the
/// applicant's address, verifies the address, uploads a selfie with the
/// applicant, and records the FI outcome (Positive / Negative). Static
/// placeholder data — values will come from the FI API when it's wired.
class FieldInvestigationScreen extends StatefulWidget {
  const FieldInvestigationScreen({super.key, required this.lead});
  final LeadItem lead;

  @override
  State<FieldInvestigationScreen> createState() =>
      _FieldInvestigationScreenState();
}

class _FieldInvestigationScreenState extends State<FieldInvestigationScreen> {
  bool _locationCaptured = false;
  bool _capturing = false; // native location capture in flight
  String _captureMessage = ''; // server message from the SDK on success
  String _captureCoords = ''; // "28.4595° N, 77.0266° E"
  String _captureAddress = ''; // reverse-geocoded address from the SDK
  double? _captureLat; // raw latitude from the SDK (for submit)
  double? _captureLng; // raw longitude from the SDK (for submit)
  bool _submitting = false; // Submit & Proceed in flight
  // Address-match + FV-status options come from the API (dynamic chips).
  List<StatusOption> _addressOptions = [];
  List<StatusOption> _fvOptions = [];
  String? _addressMatchValue; // selected addressMatch option value
  String? _fvStatusValue; // selected FV status option value
  // Selfies are uploaded independently — applicant → FV_SELFIE,
  // co-applicant → CO_FV_SELFIE (POST /application/upload).
  final _appRepo = ApplicationRepository();
  File? _applicantSelfie;
  File? _coApplicantSelfie;
  String? _applicantSelfieUrl; // existing selfie from the server (if any)
  String? _coApplicantSelfieUrl;
  bool _uploadingApplicant = false;
  bool _uploadingCoApplicant = false;
  bool _applicantUploaded = false;
  bool _coApplicantUploaded = false;
  bool _removingApplicant = false;
  bool _removingCoApplicant = false;
  final _reasonCtrl = TextEditingController();
  final _remarkCtrl = TextEditingController();
  bool _declared = false;

  // Applicant/header details from POST /field-verification/details.
  final _leadRepo = LeadRepository();
  ApplicantDetails? _applicant;
  String? _loanId; // loanDetails.loanId — shown in the header
  Stage? _stage; // current stage → stageId/stageType on submit
  bool _loadingDetails = true;

  bool get _isNegative => _fvStatusValue == 'negative';

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  // Fetch the field-verification details (same API as the Loan Approved screen)
  // to fill the header. Best-effort — on error the header falls back to the lead.
  Future<void> _loadDetails() async {
    try {
      final data = await _leadRepo.getFinancialApproval(leadId: widget.lead.id);
      if (!mounted) return;
      setState(() {
        _applicant = data.applicant;
        _loanId = data.loan.loanId;
        _stage = data.stageByKey('FIELD_INVESTIGATION') ?? data.currentStage;
        _addressOptions = data.addressMatchStatusOptions;
        _fvOptions = data.fvStatusOptions;
        // Default selections = first option (if not already chosen).
        _addressMatchValue ??=
            _addressOptions.isNotEmpty ? _addressOptions.first.value : null;
        _fvStatusValue ??=
            _fvOptions.isNotEmpty ? _fvOptions.first.value : null;
        // Existing selfies (viewable url) from a previous FI.
        final aUrl = data.selfies.applicant?.url ?? '';
        final cUrl = data.selfies.coApplicant?.url ?? '';
        if (aUrl.isNotEmpty) {
          _applicantSelfieUrl = aUrl;
          _applicantUploaded = true;
        }
        if (cUrl.isNotEmpty) {
          _coApplicantSelfieUrl = cUrl;
          _coApplicantUploaded = true;
        }
        // Pre-fill from an already-submitted Field Investigation (if any).
        final fv = data.fieldVerification;
        if (fv != null) {
          if (fv.geoAddress.isNotEmpty) {
            _captureAddress = fv.geoAddress; // Address (As per field visit)
            _captureLat = double.tryParse(fv.latitude);
            _captureLng = double.tryParse(fv.longitude);
            _captureCoords = _formatCoords(_captureLat, _captureLng);
            _locationCaptured = true;
          }
          if (fv.addressMatchStatus != null) {
            _addressMatchValue = fv.addressMatchStatus!.value;
          }
          if (fv.status != null) _fvStatusValue = fv.status!.value;
          if (fv.remarks.isNotEmpty) _remarkCtrl.text = fv.remarks;
          if (fv.reason.isNotEmpty) _reasonCtrl.text = fv.reason;
        }
        _loadingDetails = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingDetails = false);
    }
  }

  // Colors for the option chips, resolved from the option value.
  Color _addressColor(String value) {
    final v = value.toLowerCase();
    if (v.contains('no_match') || v.contains('not')) return AppColors.statusRed;
    if (v.contains('minor')) return AppColors.chartProgress;
    return AppColors.success; // match
  }

  Color _fvColor(String value) =>
      value.toLowerCase().contains('negative')
          ? AppColors.statusRed
          : AppColors.success;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    _remarkCtrl.dispose();
    super.dispose();
  }

  // Capture Current Location — calls the native Surepass send-location SDK
  // (permission handled natively). Marks captured + shows the server message.
  Future<void> _captureLocation() async {
    if (_capturing) return;
    setState(() => _capturing = true);
    try {
      final res = await SendLocationChannel.captureLocation();
      debugPrint('[FieldInvestigation] capture result → success=${res.success} '
          'statusCode=${res.statusCode} id=${res.id} code=${res.code} '
          'lat=${res.latitude} lng=${res.longitude} address=${res.address} '
          'message="${res.message}"');
      if (!mounted) return;
      if (res.success) {
        setState(() {
          _locationCaptured = true;
          _captureMessage = res.message;
          _captureLat = res.latitude;
          _captureLng = res.longitude;
          _captureCoords = _formatCoords(res.latitude, res.longitude);
          _captureAddress = res.address ?? '';
        });
      } else {
        _snack(res.message.isEmpty ? 'Could not capture location.' : res.message,
            error: true);
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  // "28.4595° N, 77.0266° E" from the SDK's latitude/longitude.
  String _formatCoords(double? lat, double? lng) {
    if (lat == null || lng == null) return '';
    final ns = lat >= 0 ? 'N' : 'S';
    final ew = lng >= 0 ? 'E' : 'W';
    return '${lat.abs().toStringAsFixed(4)}° $ns, '
        '${lng.abs().toStringAsFixed(4)}° $ew';
  }

  // Colored snackbar: green for success, red for errors.
  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: error ? AppColors.statusRed : AppColors.success,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // Today as YYYY-MM-DD for `verificationDate`.
  String _today() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${two(n.month)}-${two(n.day)}';
  }

  // Submit the Field Investigation (POST /field-verification/create). lat/long +
  // geoAddress come from the SDK; applicationId = applicantDetails.id.
  Future<void> _submit() async {
    if (_submitting || !_canSubmit) return;
    final appId = _applicant?.id ?? '';
    if (appId.isEmpty) {
      _snack('Application ID not available for this lead.', error: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      final msg = await _leadRepo.createFieldVerification(
        applicationId: int.tryParse(appId) ?? appId,
        latitude: _captureLat ?? 0,
        longitude: _captureLng ?? 0,
        geoAddress: _captureAddress,
        addressMatchStatus: _addressMatchValue ?? '',
        status: _fvStatusValue ?? '',
        remarks: _remarkCtrl.text.trim(),
        reason: _isNegative ? _reasonCtrl.text.trim() : '',
        verificationDate: _today(),
        stageId: int.tryParse(_stage?.stageId ?? '') ?? (_stage?.stageId ?? ''),
        stageType: _stage?.stageType ?? '',
      );
      if (!mounted) return;
      _snack(msg);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ESignPendingScreen(lead: widget.lead),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString().replaceFirst('ApiException: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // Same styled bottom sheet as the Upload Documents screen (rounded top, drag
  // handle, purple icons, title + subtitle). Selfie is image-only → Camera /
  // Gallery.
  Future<ImageSource?> _pickImageSource() {
    final p = context.palette;
    return showModalBottomSheet<ImageSource>(
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
              leading: const Icon(Icons.photo_camera, color: AppColors.purple),
              title: Text('Camera',
                  style:
                      TextStyle(color: p.title, fontWeight: FontWeight.w600)),
              subtitle: Text('Capture a selfie photo',
                  style: TextStyle(color: p.subtitle, fontSize: 12)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading:
                  const Icon(Icons.photo_library, color: AppColors.purple),
              title: Text('Gallery',
                  style:
                      TextStyle(color: p.title, fontWeight: FontWeight.w600)),
              subtitle: Text('Choose an image (png/jpg/jpeg)',
                  style: TextStyle(color: p.subtitle, fontSize: 12)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // Pick + upload a selfie for the applicant (FV_SELFIE) or co-applicant
  // (CO_FV_SELFIE). Uploads immediately so each side is saved independently.
  Future<void> _captureSelfie({required bool isCoApplicant}) async {
    if (isCoApplicant ? _uploadingCoApplicant : _uploadingApplicant) return;
    final source = await _pickImageSource();
    if (source == null) return;
    final picked = await ImagePicker().pickImage(source: source);
    if (picked == null || !mounted) return;
    // Crop step — same free-form cropper as the Upload Documents screen.
    final cropped = await _cropImage(picked.path);
    if (cropped == null || !mounted) return; // user cancelled the crop
    final file = File(cropped);
    setState(() {
      if (isCoApplicant) {
        _coApplicantSelfie = file;
        _coApplicantUploaded = false;
      } else {
        _applicantSelfie = file;
        _applicantUploaded = false;
      }
    });
    await _uploadSelfie(isCoApplicant: isCoApplicant, path: cropped);
  }

  /// Free/manual cropper (same config as Upload Documents). Returns the cropped
  /// file path, or null if the user cancelled.
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

  Future<void> _uploadSelfie(
      {required bool isCoApplicant, required String path}) async {
    final field = isCoApplicant ? 'CO_FV_SELFIE' : 'FV_SELFIE';
    setState(() {
      if (isCoApplicant) {
        _uploadingCoApplicant = true;
      } else {
        _uploadingApplicant = true;
      }
    });
    try {
      await _appRepo
          .uploadFiles(leadId: widget.lead.id, files: {field: path});
      if (!mounted) return;
      setState(() {
        if (isCoApplicant) {
          _coApplicantUploaded = true;
        } else {
          _applicantUploaded = true;
        }
      });
      _snack(isCoApplicant
          ? 'Co-applicant selfie uploaded'
          : 'Applicant selfie uploaded');
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString().replaceFirst('ApiException: ', ''), error: true);
    } finally {
      if (mounted) {
        setState(() {
          if (isCoApplicant) {
            _uploadingCoApplicant = false;
          } else {
            _uploadingApplicant = false;
          }
        });
      }
    }
  }

  // Remove a selfie — deletes it on the server (POST /application/delete-document
  // with the same code used on upload: FV_SELFIE / CO_FV_SELFIE), then clears it.
  Future<void> _removeSelfie({required bool isCoApplicant}) async {
    if (isCoApplicant ? _removingCoApplicant : _removingApplicant) return;
    final field = isCoApplicant ? 'CO_FV_SELFIE' : 'FV_SELFIE';
    setState(() {
      if (isCoApplicant) {
        _removingCoApplicant = true;
      } else {
        _removingApplicant = true;
      }
    });
    try {
      await _appRepo.deleteDocument(leadId: widget.lead.id, docCode: field);
      if (!mounted) return;
      setState(() {
        if (isCoApplicant) {
          _coApplicantSelfie = null;
          _coApplicantSelfieUrl = null;
          _coApplicantUploaded = false;
        } else {
          _applicantSelfie = null;
          _applicantSelfieUrl = null;
          _applicantUploaded = false;
        }
      });
      _snack(isCoApplicant
          ? 'Co-applicant selfie removed'
          : 'Applicant selfie removed');
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString().replaceFirst('ApiException: ', ''), error: true);
    } finally {
      if (mounted) {
        setState(() {
          if (isCoApplicant) {
            _removingCoApplicant = false;
          } else {
            _removingApplicant = false;
          }
        });
      }
    }
  }

  // Submit is enabled only when every required part is done:
  //  • field-visit location/address captured
  //  • an Address Match Status chosen
  //  • both applicant & co-applicant selfies present
  //  • an FI status chosen
  //  • the declaration checkbox ticked
  bool get _hasApplicantSelfie =>
      _applicantSelfie != null || _applicantSelfieUrl != null;
  bool get _hasCoApplicantSelfie =>
      _coApplicantSelfie != null || _coApplicantSelfieUrl != null;
  bool get _canSubmit =>
      _captureAddress.isNotEmpty &&
      _addressMatchValue != null &&
      _hasApplicantSelfie &&
      _hasCoApplicantSelfie &&
      _fvStatusValue != null &&
      _declared;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final canSubmit = _canSubmit && !_submitting;
    return AppFlowScaffold(
      title: 'Field Investigation',
      bottomBar: InteractionBottomBar(
        actionLabel: 'Submit & Proceed',
        enabled: canSubmit,
        onAction: _submit,
      ),
      body: Stack(
        children: [
          ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        children: [
          _FiHeaderCard(
            lead: widget.lead,
            applicant: _applicant,
            loanId: _loanId,
            loading: _loadingDetails,
          ),
          const SizedBox(height: 16),

          // Visit & Address Verification
          FlowCard(
            heading: 'Visit & Address Verification',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    "Capture your current location at the Applicant's Address.",
                    style: TextStyle(fontSize: 12.5, color: p.subtitle),
                  ),
                ),
                const _MapPlaceholder(),
                const SizedBox(height: 14),
                OutlinedButton(
                  onPressed: _capturing ? null : _captureLocation,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _capturing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.primary),
                        )
                      : const Text('Capture Current Location',
                          style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary)),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text('GPS coordinates will be recorded',
                      style: TextStyle(fontSize: 12.5, color: p.subtitle)),
                ),
                if (_locationCaptured) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.success.withValues(alpha: 0.30)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.success,
                          ),
                          child: const Icon(Icons.check,
                              size: 18, color: Colors.white),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Location Captured Successfully.',
                                  style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.success)),
                              if (_captureMessage.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(_captureMessage,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.success)),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_captureCoords.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(text: 'Location Captured:  '),
                          TextSpan(
                            text: _captureCoords,
                            style: TextStyle(
                                color: p.title, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      style: TextStyle(fontSize: 13, color: p.subtitle),
                    ),
                  ], 
                  // if (_captureAddress.isNotEmpty) ...[
                  //   const SizedBox(height: 6),
                  //   Text.rich(
                  //     TextSpan(
                  //       children: [
                  //         const TextSpan(text: 'Address:  '),
                  //         TextSpan(
                  //           text: _captureAddress,
                  //           style: TextStyle(
                  //               color: p.title, fontWeight: FontWeight.w600),
                  //         ),
                  //       ],
                  //     ),
                  //     style:
                  //         TextStyle(fontSize: 13, height: 1.4, color: p.subtitle),
                  //   ),
                  // ],
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Address Verification
          FlowCard(
            heading: 'Address Verification',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AddressBox(
                  caption: '(As per the application)',
                  address: (_applicant?.address.trim().isNotEmpty ?? false)
                      ? _applicant!.address
                      : (_loadingDetails
                          ? 'Loading…'
                          : 'Not available.'),
                ),
                const SizedBox(height: 12),
                // Filled from the location captured via the send-location SDK
                // (reverse-geocoded address). Empty until the RM captures it.
                _AddressBox(
                  caption: '(As per field visit)',
                  address: _captureAddress.isNotEmpty
                      ? _captureAddress
                      : 'Tap "Capture Current Location" above to fill the '
                          'field-visit address.',
                ),
                const SizedBox(height: 14),
                Text('Address Match Status',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: p.title)),
                const SizedBox(height: 10),
                // Dynamic — options come from the API (addressMatchStatusOptions).
                Row(
                  children: [
                    for (var i = 0; i < _addressOptions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      _MatchChip(
                        label: _addressOptions[i].displayName,
                        color: _addressColor(_addressOptions[i].value),
                        icon: Icons.check_circle_outline,
                        selected:
                            _addressMatchValue == _addressOptions[i].value,
                        onTap: () => setState(() =>
                            _addressMatchValue = _addressOptions[i].value),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Selfie With Applicant → FV_SELFIE
          FlowCard(
            heading: 'Selfie With Applicant',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text('Capture & upload selfie with the applicant',
                      style: TextStyle(fontSize: 12.5, color: p.subtitle)),
                ),
                _SelfieUpload(
                  file: _applicantSelfie,
                  networkUrl: _applicantSelfieUrl,
                  uploading: _uploadingApplicant,
                  uploaded: _applicantUploaded,
                  onTap: () => _captureSelfie(isCoApplicant: false),
                ),
                if (_applicantSelfie != null || _applicantSelfieUrl != null)
                  _RemoveSelfieButton(
                    removing: _removingApplicant,
                    onTap: () => _removeSelfie(isCoApplicant: false),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Selfie With Co-Applicant → CO_FV_SELFIE
          FlowCard(
            heading: 'Selfie With Co-Applicant',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text('Capture & upload selfie with the co-applicant',
                      style: TextStyle(fontSize: 12.5, color: p.subtitle)),
                ),
                _SelfieUpload(
                  file: _coApplicantSelfie,
                  networkUrl: _coApplicantSelfieUrl,
                  uploading: _uploadingCoApplicant,
                  uploaded: _coApplicantUploaded,
                  onTap: () => _captureSelfie(isCoApplicant: true),
                ),
                if (_coApplicantSelfie != null || _coApplicantSelfieUrl != null)
                  _RemoveSelfieButton(
                    removing: _removingCoApplicant,
                    onTap: () => _removeSelfie(isCoApplicant: true),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // FI Status
          FlowCard(
            heading: 'FI Status',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Dynamic — options come from the API (fvStatusOptions).
                Row(
                  children: [
                    for (var i = 0; i < _fvOptions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(
                        child: _FiStatusChip(
                          label: _fvOptions[i].displayName,
                          color: _fvColor(_fvOptions[i].value),
                          icon: _fvColor(_fvOptions[i].value) ==
                                  AppColors.statusRed
                              ? Icons.cancel
                              : Icons.check_circle,
                          selected: _fvStatusValue == _fvOptions[i].value,
                          onTap: () => setState(
                              () => _fvStatusValue = _fvOptions[i].value),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                _FieldLabel('Reason', hint: '(If negative selected)'),
                const SizedBox(height: 6),
                _InputBox(
                  controller: _reasonCtrl,
                  hint: 'Enter Reason',
                  enabled: _isNegative,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Remark
          _FieldLabel('Remark', hint: '(If any)'),
          const SizedBox(height: 6),
          _InputBox(
            controller: _remarkCtrl,
            hint: 'Enter remark',
            minLines: 3,
            maxLines: 4,
          ),
          const SizedBox(height: 14),

          // Declaration
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: _declared,
                  onChanged: (v) => setState(() => _declared = v ?? false),
                  activeColor: AppColors.purple,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'I hereby declare that the above details are true and '
                    'correct to the best of my knowledge and belief.',
                    style: TextStyle(
                        fontSize: 12.5, height: 1.4, color: p.subtitle),
                  ),
                ),
              ),
            ],
          ),
        ],
          ),
          // Loader overlays the form while data loads or the FI submits.
          if (_loadingDetails || _submitting)
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

/// Header: Loan ID, applicant name, phone + location.
class _FiHeaderCard extends StatelessWidget {
  const _FiHeaderCard({
    required this.lead,
    required this.applicant,
    required this.loanId,
    required this.loading,
  });
  final LeadItem lead;
  final ApplicantDetails? applicant;
  final String? loanId;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    String pick(String? a, String fallback) =>
        (a != null && a.trim().isNotEmpty) ? a : fallback;

    // Prefer /field-verification/details values, fall back to the lead.
    final loanIdText = pick(loanId, '—');
    final name = pick(applicant?.applicantName, lead.name.isEmpty ? '—' : lead.name);
    final mobile =
        pick(applicant?.mobileNumber, lead.mobile.isEmpty ? '—' : lead.mobile);
    final location = lead.location;

    return InteractionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Loan ID',
                  style: TextStyle(fontSize: 12.5, color: p.subtitle)),
              if (loading) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.6, color: AppColors.purple),
                ),
              ],
            ],
          ),
          const SizedBox(height: 3),
          Text(loanIdText,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: p.title)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: p.fieldBorder),
          ),
          Text(name,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: p.title)),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.call, size: 16, color: p.subtitle),
              const SizedBox(width: 5),
              Text(mobile,
                  style: TextStyle(fontSize: 13.5, color: p.subtitle)),
              if (location.isNotEmpty) ...[
                const SizedBox(width: 14),
                Icon(Icons.location_on_outlined, size: 17, color: p.subtitle),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(location,
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

/// Static map preview image shown above the Capture button.
class _MapPlaceholder extends StatelessWidget {
  const _MapPlaceholder();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 150,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.fieldBorder),
        ),
        child: Image.asset(
          AppAssets.sendLocationMap,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            color: p.otpBoxBg,
            alignment: Alignment.center,
            child:
                const Icon(Icons.location_on, size: 40, color: AppColors.purple),
          ),
        ),
      ),
    );
  }
}

/// Read-only address box with a "(caption)" note next to the "Address" label.
class _AddressBox extends StatelessWidget {
  const _AddressBox({required this.caption, required this.address});
  final String caption;
  final String address;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.fieldBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.fieldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                    text: 'Address ',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: p.title)),
                TextSpan(
                    text: caption,
                    style: TextStyle(fontSize: 12, color: p.subtitle)),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Text(address,
              style: TextStyle(fontSize: 13, height: 1.4, color: p.title)),
        ],
      ),
    );
  }
}

/// Address-match segmented chip (Match / Minor Difference / Not Match).
class _MatchChip extends StatelessWidget {
  const _MatchChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
    this.icon,
  });
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.10) : p.fieldBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: selected ? color : p.fieldBorder,
                width: selected ? 1.4 : 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (selected && icon != null) ...[
                Icon(icon, size: 15, color: color),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: selected ? color : p.subtitle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// FI-status chip (Positive / Negative) with an always-visible status icon.
class _FiStatusChip extends StatelessWidget {
  const _FiStatusChip({
    required this.label,
    required this.color,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final Color color;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.10) : p.fieldBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? color : p.fieldBorder,
              width: selected ? 1.4 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: color)),
          ],
        ),
      ),
    );
  }
}

/// "Remove" action under a selfie — deletes it on the server.
class _RemoveSelfieButton extends StatelessWidget {
  const _RemoveSelfieButton({required this.removing, required this.onTap});
  final bool removing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        onPressed: removing ? null : onTap,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.statusRed,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: const Size(0, 0),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: removing
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.statusRed),
              )
            : const Icon(Icons.delete_outline, size: 18),
        label: const Text('Remove',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

/// Selfie upload area — empty drop-zone, or a full photo preview (whole image
/// visible, tap to zoom) with an edit badge (re-pick), uploading spinner, and a
/// green "uploaded" check.
class _SelfieUpload extends StatelessWidget {
  const _SelfieUpload({
    required this.file,
    required this.onTap,
    this.networkUrl,
    this.uploading = false,
    this.uploaded = false,
  });
  final File? file; // freshly picked local selfie
  final String? networkUrl; // existing selfie from the server (if any)
  final VoidCallback onTap; // pick / re-pick
  final bool uploading;
  final bool uploaded;

  bool get _hasImage =>
      file != null || (networkUrl != null && networkUrl!.trim().isNotEmpty);

  // Local file takes precedence; otherwise the server url.
  static const _imgError = Center(
      child: Icon(Icons.broken_image_outlined,
          color: Colors.white54, size: 32));

  Widget _image(BoxFit fit) {
    if (file != null) return Image.file(file!, fit: fit);
    final src = (networkUrl ?? '').trim();
    // http(s) → network; otherwise treat as base64 (data-URI or raw base64).
    if (src.startsWith('http')) {
      return Image.network(
        src,
        fit: fit,
        loadingBuilder: (c, w, prog) => prog == null
            ? w
            : const Center(
                child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))),
        errorBuilder: (_, _, _) => _imgError,
      );
    }
    try {
      final comma = src.indexOf(',');
      final b64 = comma >= 0 ? src.substring(comma + 1) : src;
      return Image.memory(base64Decode(b64),
          fit: fit, errorBuilder: (_, _, _) => _imgError);
    } catch (_) {
      return _imgError;
    }
  }

  // Full-screen, zoomable view of the selfie.
  void _viewFull(BuildContext context) {
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
              child: Center(child: _image(BoxFit.contain)),
            ),
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
    final p = context.palette;
    if (!_hasImage) {
      return GestureDetector(
        onTap: uploading ? null : onTap,
        child: Container(
          height: 130,
          width: double.infinity,
          decoration: BoxDecoration(
            color: p.fieldBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.fieldBorder),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                AppAssets.photoGallery,
                width: 46,
                height: 46,
                errorBuilder: (_, _, _) =>
                    Icon(Icons.image_outlined, size: 40, color: p.iconGrey),
              ),
              const SizedBox(height: 8),
              Text('Capture / choose a selfie photo',
                  style: TextStyle(fontSize: 12.5, color: p.subtitle)),
            ],
          ),
        ),
      );
    }
    // Photo present → show the WHOLE image (contain) on a dark frame.
    return Container(
      height: 220,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.fieldBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTap: uploading ? null : () => _viewFull(context),
            child: _image(BoxFit.contain),
          ),
          // Top-right: green check when uploaded, else an edit (re-pick) button.
          Positioned(
            right: 8,
            top: 8,
            child: uploaded
                ? Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                        shape: BoxShape.circle, color: AppColors.success),
                    child:
                        const Icon(Icons.check, size: 16, color: Colors.white),
                  )
                : GestureDetector(
                    onTap: uploading ? null : onTap,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(
                          shape: BoxShape.circle, color: Colors.black54),
                      child: const Icon(Icons.edit,
                          size: 16, color: Colors.white),
                    ),
                  ),
          ),
          if (uploading)
            Container(
              color: Colors.black45,
              alignment: Alignment.center,
              child: const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Label (hint)" line above an input field.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label, {this.hint});
  final String label;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
              text: label,
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: p.title)),
          if (hint != null)
            TextSpan(
                text: '  $hint',
                style: TextStyle(fontSize: 12, color: p.subtitle)),
        ],
      ),
    );
  }
}

/// Bordered text input.
class _InputBox extends StatelessWidget {
  const _InputBox({
    required this.controller,
    required this.hint,
    this.enabled = true,
    this.minLines = 1,
    this.maxLines = 1,
  });
  final TextEditingController controller;
  final String hint;
  final bool enabled;
  final int minLines;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return TextField(
      controller: controller,
      enabled: enabled,
      minLines: minLines,
      maxLines: maxLines < minLines ? minLines : maxLines,
      style: TextStyle(fontSize: 14, color: p.title),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 14, color: p.hint),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        filled: true,
        fillColor: enabled ? p.fieldBg : p.otpBoxBg,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.fieldBorder),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.fieldBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
      ),
    );
  }
}
