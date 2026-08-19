import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/models/lead_item.dart';
import '../../data/models/person_detail.dart';
import '../../data/models/uploaded_doc.dart';
import '../../data/repositories/application_repository.dart';
import '../../theme/app_colors.dart';
import '../screens/upload_documents_screen.dart';
import '../widgets/doc_thumb.dart';
import '../widgets/interaction_ui.dart';
import 'application_flow_ui.dart';
import 'applicant_consent_screen.dart';

/// Step 2 of 5 — Application Details. Real applicant + co-applicant data from
/// `POST /application/details` (null fields show blank). Proceed (Co-Applicant
/// tab) opens the Consent Mode popup.
class ApplicationDetailsScreen extends StatefulWidget {
  const ApplicationDetailsScreen({
    super.key,
    required this.lead,
    this.stageId = '',
    this.stageType = '',
  });
  final LeadItem lead;
  final String stageId; // applicationStages[].id of this (KYC) stage
  final String stageType; // applicationStages[].stageType (e.g. "KYC")

  @override
  State<ApplicationDetailsScreen> createState() =>
      _ApplicationDetailsScreenState();
}

class _ApplicationDetailsScreenState extends State<ApplicationDetailsScreen> {
  final ApplicationRepository _appRepo = ApplicationRepository();
  ApplicationDetails? _details;
  bool _loading = true;
  String? _error;

  int _tab = 0; // 0 = Applicant, 1 = Co-Applicant
  bool _appSameAddr = true;
  bool _coSameAddr = true;
  // Marital status & relation — stored as the LOWERCASE key (e.g. 'married',
  // 'husband') so it matches the dropdown options; the dropdown shows the API
  // label. Both the keys AND labels come from the API (marital / relationship
  // lists). Empty = nothing selected → the dropdown shows its placeholder.
  String _maritalStatus = '';
  String _relation = '';

  // The marital/relationship VALUE sent to the API must be UPPERCASE
  // (e.g. MARRIED, UNMARRIED, HUSBAND). Internal state stays lowercase for
  // dropdown matching; uppercase only when passing to the backend.
  String get _maritalForApi => _maritalStatus.trim().toUpperCase();
  String get _relationForApi => _relation.trim().toUpperCase();
  // Current-address-proof type (shown only when "No" is selected).
  // Current-address-proof TYPE key (from the API addressType options); set in
  // _load to the first option, sent as proof_Type / co_proof_Type on upload.
  String _appProof = '';
  String _coProof = '';
  // Uploaded address-proof file name + local path (for the thumbnail preview)
  // + in-progress flags (per applicant). Path is null for a server-only file.
  String? _appProofName;
  String? _coProofName;
  String? _appProofPath;
  String? _coProofPath;
  // Server THUMBNAIL bytes (small base64 image) of a previously-uploaded proof —
  // shown when there's no fresh local file (path). Null for a PDF / no preview.
  Uint8List? _appProofPreview;
  Uint8List? _coProofPreview;
  // Server THUMBNAIL url (new /application/details shape) — used instead of the
  // base64 bytes when the API sends a URL. '' when none / PDF.
  String _appProofUrl = '';
  String _coProofUrl = '';
  // Server documentId of a previously-uploaded proof — used to fetch the FULL
  // file on demand (POST /application/document) when the thumbnail is tapped.
  String? _appProofId;
  String? _coProofId;
  // Data extracted from the proof upload response (No flow) — shown instantly:
  // currAddress → Current Address, consumerName → Owner Name,
  // consumerNumber → Bill / Reference Number. Cleared on Remove.
  String? _appCurrAddr, _appConsumerName, _appConsumerNo;
  String? _coCurrAddr, _coConsumerName, _coConsumerNo;
  bool _uploadingApp = false;
  bool _uploadingCo = false;
  bool _removingApp = false;
  bool _removingCo = false;
  bool _saving = false; // Proceed → save-applicant call in progress

  // Residence Type — a fixed 3-option dropdown. Stored as the UPPERCASE key
  // (SELF_OWNED / FAMILY_OWNED / RENTED); the dropdown shows the friendly label.
  // Pre-selected from the /location/checksum `ownership` response — and the RM
  // can also pick it manually (e.g. when the checksum returns nothing).
  // Null until the checksum has run for that person → falls back to the API's
  // residenceType. [_checkingOwnership] shows a loader while the call is running.
  String? _appOwnership;
  String? _coOwnership;
  bool _checkingOwnership = false;

  // The Residence Type dropdown options (key → label).
  static const Map<String, String> _residenceItems = {
    'SELF_OWNED': 'Self Owned',
    'FAMILY_OWNED': 'Family Owned',
    'RENTED': 'Rented',
  };

  // Normalise any residence value (key or label) to one of the option keys
  // (e.g. "Family Owned" / "family_owned" → "FAMILY_OWNED"); '' if unknown.
  String _residenceKey(String raw) {
    final k = raw.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '_');
    return _residenceItems.containsKey(k) ? k : '';
  }

  static const List<String> _allowedExt = ['pdf', 'png', 'jpg', 'jpeg'];
  static const int _maxUploadBytes = 10 * 1024 * 1024; // 10 MB

  // Editable mobile-number fields (prefilled from the API phoneNumber).
  final TextEditingController _appMobileCtrl = TextEditingController();
  final TextEditingController _coMobileCtrl = TextEditingController();

  @override
  void dispose() {
    _appMobileCtrl.dispose();
    _coMobileCtrl.dispose();
    super.dispose();
  }

  // key -> label maps for the dropdowns — built purely from the API option
  // lists (marital / relationship / addressType from /application/details).
  Map<String, String> get _proofItems => {
        for (final o in _details?.addressTypeOptions ?? const [])
          o.value: o.displayName
      };

  Map<String, String> get _maritalItems => {
        for (final o in _details?.maritalOptions ?? const [])
          o.value: o.displayName
      };

  Map<String, String> get _relationItems => {
        for (final o in _details?.relationshipOptions ?? const [])
          o.value: o.displayName
      };

  @override
  void initState() {
    super.initState();
    // Re-evaluate the Proceed button as the user types a mobile number.
    _appMobileCtrl.addListener(_onFormChanged);
    _coMobileCtrl.addListener(_onFormChanged);
    _load();
  }

  void _onFormChanged() => setState(() {});

  // Proceed is allowed only when every required field is filled:
  //  • applicant + co-applicant mobile numbers
  //  • marital status (applicant) + relationship (co-applicant)
  //  • when "current address same as Aadhar?" is No, the address proof must be
  //    uploaded for that person.
  bool get _canProceed {
    if (_loading || _error != null) return false;
    // Both applicant + co-applicant mobile numbers must be EXACTLY 10 digits.
    final tenDigits = RegExp(r'^\d{10}$');
    if (!tenDigits.hasMatch(_appMobileCtrl.text.trim())) return false;
    if (!tenDigits.hasMatch(_coMobileCtrl.text.trim())) return false;
    if (_maritalStatus.isEmpty || _relation.isEmpty) return false;
    if (!_appSameAddr && _appProofName == null) return false;
    if (!_coSameAddr && _coProofName == null) return false;
    return true;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await _appRepo.getApplicationDetails(leadId: widget.lead.id);
      if (!mounted) return;
      setState(() {
        _details = d;
        // "Is current address same as Aadhar address?" follows the API's
        // sameAsPermanent — true → Yes, false → No (defaults to Yes if missing).
        _appSameAddr = d.applicant?.sameAsPermanent ?? true;
        _coSameAddr = d.coApplicant?.sameAsPermanent ?? true;
        // Prefill the editable mobile fields from the API.
        _appMobileCtrl.text = d.applicant?.phoneNumber ?? '';
        _coMobileCtrl.text = d.coApplicant?.phoneNumber ?? '';
        // Pre-select the dropdowns from the API's saved value when it's a valid
        // option; otherwise leave empty so the placeholder shows.
        final marital = d.applicant?.maritalStatus ?? '';
        _maritalStatus = _maritalItems.containsKey(marital) ? marital : '';
        final rel = d.coApplicant?.relationship ?? '';
        _relation = _relationItems.containsKey(rel) ? rel : '';
        // Pre-select the Residence Type dropdowns from the API's saved
        // residenceType (e.g. "FAMILY_OWNED"). Normalised to an option key;
        // empty when unknown so the placeholder shows. The checksum call may
        // later override this with the verified ownership.
        final appRes = _residenceKey(d.applicant?.residenceType ?? '');
        if (appRes.isNotEmpty) _appOwnership = appRes;
        final coRes = _residenceKey(d.coApplicant?.residenceType ?? '');
        if (coRes.isNotEmpty) _coOwnership = coRes;
        // Current Address Proof type starts empty → shows the "Select Address
        // Proof" placeholder; the user must pick one.
        _appProof = '';
        _coProof = '';
        // Pre-fill a previously-uploaded Current Address proof (No flow) from
        // applicantDocs / coApplicantDocs so it shows as already uploaded.
        _applyServerProof(d.applicantProof, isCo: false);
        _applyServerProof(d.coApplicantProof, isCo: true);
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load details. Please try again.';
        _loading = false;
      });
    }
  }

  // Silently re-fetch the details (e.g. after a current-address-proof upload
  // populates the current address) — updates only [_details], so the user's
  // form selections (mobile, radios, dropdowns) are preserved.
  Future<void> _refreshDetails() async {
    try {
      final d = await _appRepo.getApplicationDetails(leadId: widget.lead.id);
      if (mounted) setState(() => _details = d);
    } catch (_) {
      /* keep the current details on any error */
    }
  }

  // Show a previously-uploaded Current Address proof (from applicantDocs /
  // coApplicantDocs) as already uploaded — file name + image preview (base64).
  void _applyServerProof(UploadedDoc? doc, {required bool isCo}) {
    if (doc == null) return;
    final name = doc.fileName.isNotEmpty ? doc.fileName : doc.originalName;
    final thumb = doc.isPdf ? null : doc.thumbnailBytes; // small thumbnail
    final thumbUrl = doc.isPdf ? '' : doc.thumbnailUrl; // url thumbnail (new API)
    if (isCo) {
      _coProofName = name;
      _coProofPreview = thumb;
      _coProofUrl = thumbUrl;
      _coProofId = doc.id;
    } else {
      _appProofName = name;
      _appProofPreview = thumb;
      _appProofUrl = thumbUrl;
      _appProofId = doc.id;
    }
  }

  // Send the full applicant/co-applicant objects (from /details) merged with
  // the user's edits to the given save-applicant field shape.
  Map<String, dynamic> _personPayload(
    Map<String, dynamic>? raw, {
    required bool sameAsPermanent,
    required String mobile,
    String? maritalStatus,
    String? relationship,
    String? residenceType,
    String? consumerName,
  }) {
    final m = Map<String, dynamic>.from(raw ?? const {});
    m['sameAsPermanent'] = sameAsPermanent;
    // The server doesn't populate `permanentAddress` (comes null) — the real
    // permanent/Aadhar address lives in `address`. Fill permanentAddress from
    // it so we never send null.
    final perm = (m['permanentAddress']?.toString().trim().isNotEmpty ?? false)
        ? m['permanentAddress'].toString()
        : (m['address']?.toString() ?? '');
    m['permanentAddress'] = perm;
    // Yes → current address is the SAME as permanent: send the permanent
    // address as currAddress (don't leave it empty).
    if (sameAsPermanent) {
      m['currAddress'] = perm;
    }
    // `ownerName` should carry the consumerName in EVERY case (Yes/No) so it's
    // never empty. Prefer the resolved consumerName passed in (state/OCR/details),
    // else the raw one.
    final consumer = (consumerName != null && consumerName.trim().isNotEmpty)
        ? consumerName.trim()
        : (m['consumerName']?.toString() ?? '');
    if (consumer.isNotEmpty) {
      m['ownerName'] = consumer;
      m['consumerName'] = consumer; // keep both in sync
    }
    m['phone_number'] = mobile; // edited mobile (server's expected key)
    m['phoneNumber'] = mobile; // keep the original key in sync too
    if (maritalStatus != null) m['maritalStatus'] = maritalStatus;
    if (relationship != null) m['relationship'] = relationship;
    // Residence Type — the selected UPPERCASE key (SELF_OWNED/FAMILY_OWNED/
    // RENTED); only sent when an option is actually selected.
    if (residenceType != null && residenceType.isNotEmpty) {
      m['residenceType'] = residenceType;
    }
    // DOB → always send yyyy-MM-dd to /application/save-applicant (server
    // format), whatever shape it came in as. Display stays dd-MM-yyyy (_fmtDob).
    final dobRaw = m['dob']?.toString() ?? '';
    if (dobRaw.isNotEmpty) m['dob'] = _toIsoDob(dobRaw);
    return m;
  }

  // Normalize any DOB shape → yyyy-MM-dd (the save-applicant server format).
  // Handles yyyy-MM-dd / ISO datetime and day-first dd-MM-yyyy or dd/MM/yyyy.
  // Empty stays empty; unknown stays as-is.
  String _toIsoDob(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return '';
    final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(v);
    if (iso != null) {
      return '${iso.group(1)}-${iso.group(2)}-${iso.group(3)}';
    }
    final dmy = RegExp(r'^(\d{1,2})[-/](\d{1,2})[-/](\d{4})').firstMatch(v);
    if (dmy != null) {
      return '${dmy.group(3)}-${dmy.group(2)!.padLeft(2, '0')}-'
          '${dmy.group(1)!.padLeft(2, '0')}';
    }
    return v;
  }

  // numeric ids are sent as ints when possible (e.g. leadId 68, stageId 2).
  dynamic _numOrString(String v) => int.tryParse(v.trim()) ?? v;

  // DOB → dd-MM-yyyy (e.g. 21-11-1993). Handles yyyy-MM-dd / ISO datetime and
  // day-first dd-MM-yyyy or dd/MM/yyyy. Empty stays empty; unknown stays as-is.
  String _fmtDob(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return '';
    final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(v);
    if (iso != null) {
      return '${iso.group(3)}-${iso.group(2)}-${iso.group(1)}';
    }
    final dmy = RegExp(r'^(\d{1,2})[-/](\d{1,2})[-/](\d{4})').firstMatch(v);
    if (dmy != null) {
      return '${dmy.group(1)!.padLeft(2, '0')}-'
          '${dmy.group(2)!.padLeft(2, '0')}-${dmy.group(3)}';
    }
    return v;
  }

  // First letter capital, rest lowercase (e.g. "female" → "Female"). Empty → ''.
  String _capFirst(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return '';
    return v[0].toUpperCase() + v.substring(1).toLowerCase();
  }

  Future<void> _proceed() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final appData = _personPayload( 
        _details?.applicantRaw,
        sameAsPermanent: _appSameAddr,
        mobile: _appMobileCtrl.text.trim(),
        // save-applicant validates these as the LOWERCASE option keys
        // (e.g. "married", "father") — the UPPERCASE form is only for the
        // /location/checksum API.
        maritalStatus: _maritalStatus,
        residenceType: _appOwnership ?? '',
        // Owner Name = consumerName in every case (OCR/state → details).
        consumerName: _appConsumerName ?? _details?.applicant?.consumerName,
      );
      final coAppData = _personPayload(
        _details?.coApplicantRaw,
        sameAsPermanent: _coSameAddr,
        mobile: _coMobileCtrl.text.trim(),
        relationship: _relation,
        residenceType: _coOwnership ?? '',
        consumerName: _coConsumerName ?? _details?.coApplicant?.consumerName,
      );
      // Send THIS page's own stage (Application Form) — resolved from the
      // details `stages` list — not whatever stage id was forwarded in.
      final stage = _details?.stageByName('Application Form');
      final stageId = stage?.stageId.isNotEmpty == true
          ? stage!.stageId
          : widget.stageId;
      final stageType =
          stage?.stageType.isNotEmpty == true ? stage!.stageType : widget.stageType;
      final res = await _appRepo.saveApplicant(
        appData: appData,
        coAppData: coAppData,
        stageId: _numOrString(stageId),
        stageType: stageType,
        status: 'draft',
        leadId: _numOrString(widget.lead.id),
        // No mode chosen here — OTP/LINK is picked later on the Consent page's
        // "Send". consentType goes empty (used after OTP verify → proceed).
        consentType: '',
      );
      if (!mounted) return;
      final ok = res is Map && (res['success'] == true || res['status'] == true);
      // Server's message (shown on both success and failure). Falls back to a
      // default only when the API doesn't send one.
      final serverMsg = (res is Map &&
              res['message'] is String &&
              (res['message'] as String).trim().isNotEmpty)
          ? (res['message'] as String).trim()
          : null;
      if (!ok) {
        _snack(serverMsg ?? 'Could not save details. Please try again.');
        return;
      }
      // Show the server's success message before moving on.
      if (serverMsg != null) _snack(serverMsg, ok: true);
      // Saved → straight to the Applicant Consent page. That page self-fetches
      // applicationId + applicant/co mobile from /application/details, and the
      // OTP/LINK choice happens there on "Send".
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ApplicantConsentScreen(lead: widget.lead),
      ));
    } on ApiException catch (e) {
      if (mounted) _snack(e.message);
    } catch (e, st) {
      // TEMP diagnostic: surface the real error so we can see what's failing.
      debugPrint('saveApplicant/proceed failed: $e\n$st');
      if (mounted) _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // The Owner Name we send as `permanentAddressProofName` = exactly what the
  // "Owner Name" row shows: Yes → the API's ownerName; No → the uploaded
  // proof's consumerName (OCR), falling back to the API consumerName.
  String _appOwnerName() {
    final a = _details?.applicant;
    return _appSameAddr
        ? (a?.ownerName ?? '')
        : (_appConsumerName ?? a?.consumerName ?? '');
  }

  String _coOwnerName() {
    final c = _details?.coApplicant;
    return _coSameAddr
        ? (c?.ownerName ?? '')
        : (_coConsumerName ?? c?.consumerName ?? '');
  }

  // `permanentAddressProofName` sent to /location/checksum = the Consumer Name
  // (uploaded-proof OCR → API consumerName). Falls back to the Owner Name only
  // when no consumer name is available (e.g. same-as-Aadhar, no proof) so the
  // checksum never receives a blank.
  String _appProofConsumerName() {
    final consumer =
        (_appConsumerName ?? _details?.applicant?.consumerName ?? '').trim();
    return consumer.isNotEmpty ? consumer : _appOwnerName();
  }

  String _coProofConsumerName() {
    final consumer =
        (_coConsumerName ?? _details?.coApplicant?.consumerName ?? '').trim();
    return consumer.isNotEmpty ? consumer : _coOwnerName();
  }

  // Call /location/checksum and put the returned `ownership` into the Residence
  // Type fields. Runs whenever marital status / relationship / the uploaded
  // proof / the same-as-Aadhar choice changes. Best-effort: on any error the
  // values already shown stay as they are.
  // Returns true when a co-applicant relationship was selected but the checksum
  // could NOT verify it (`relation.matched` != true) — in that case the
  // Residence Type is NOT auto-selected and the caller shows the
  // "upload a supporting document" dialog.
  Future<bool> _runOwnershipChecksum() async {
    final a = _details?.applicant;
    final c = _details?.coApplicant;
    if (a == null && c == null) return false;
    setState(() => _checkingOwnership = true);
    try {
      final res = await _appRepo.checkOwnership(
        applicant: {
          'fullName': a?.fullName ?? '',
          'fatherName': a?.fatherName ?? '',
          // Sent UPPERCASE (e.g. "MARRIED") as the backend expects.
          'maritalStatus': _maritalForApi,
          // Consumer Name (uploaded-proof OCR), not the plain owner name.
          'permanentAddressProofName': _appProofConsumerName(),
        },
        coApplicant: {
          'fullName': c?.fullName ?? '',
          'relationshipStatus': _relationForApi,
          'permanentAddressProofName': _coProofConsumerName(),
        },
      );
      // TEMP: log the raw checksum response to inspect the ownership payload.
      debugPrint('checksum response: $res');
      if (!mounted) return false;
      final data = (res is Map && res['data'] is Map)
          ? Map<String, dynamic>.from(res['data'] as Map)
          : <String, dynamic>{};

      // Relationship verification: when a co-applicant relationship has been
      // selected but the API couldn't verify it (`relation.matched` != true),
      // don't pre-select the Residence Type — the caller shows a dialog asking
      // for a supporting document.
      final relation = data['relation'];
      final relationMatched = relation is Map && relation['matched'] == true;
      final relationUnverified =
          c != null && _relation.trim().isNotEmpty && !relationMatched;
      if (relationUnverified) return true;

      // The API's `ownership` is one of the option keys (SELF_OWNED /
      // FAMILY_OWNED / RENTED) → pre-select that option in the dropdown.
      String ownership(dynamic person) {
        if (person is Map && person['ownership'] != null) {
          return _residenceKey(person['ownership'].toString());
        }
        return '';
      }

      final ao = ownership(data['applicant']);
      final co = ownership(data['coApplicant']);
      setState(() {
        if (ao.isNotEmpty) _appOwnership = ao;
        if (co.isNotEmpty) _coOwnership = co;
      });
      return false;
    } catch (_) {
      // Best-effort: keep whatever Residence Type is already shown.
      return false;
    } finally {
      if (mounted) setState(() => _checkingOwnership = false);
    }
  }

  // Run the checksum from the marital/relation dropdowns with a blocking modal
  // loader, so it's obvious the API is working; dismissed once it responds.
  Future<void> _runOwnershipChecksumWithLoader() async {
    final p = context.palette;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false, // can't dismiss until the API responds
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: p.cardBg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const CircularProgressIndicator(),
          ),
        ),
      ),
    );
    bool relationUnverified = false;
    try {
      relationUnverified = await _runOwnershipChecksum();
    } finally {
      // Close the loader (it's the top-most route).
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
    // Show the dialog AFTER the loader is dismissed (otherwise it'd sit behind).
    if (relationUnverified && mounted) _showRelationUnverifiedDialog();
  }

  // Shown when the checksum couldn't verify the applicant/co-applicant
  // relationship — the RM must upload a supporting document. OK dismisses it.
  void _showRelationUnverifiedDialog() {
    final p = context.palette;
    showDialog<void>(
      context: context,
      barrierDismissible: false, // must tap OK → goes back to Upload Documents
      builder: (ctx) => AlertDialog(
        backgroundColor: p.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.info_outline, color: AppColors.deepOrange),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Relationship not verified',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: p.title)),
            ),
          ],
        ),
        content: Text(
          'The relationship between the applicant and co-applicant could not '
          'be verified. Please upload a valid supporting document.',
          style: TextStyle(fontSize: 14, color: p.subtitle, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop(); // close the dialog
              // Relation couldn't be verified → send the RM back to Upload
              // Documents to re-upload a proper supporting document. Clear the
              // whole application-flow stack (this details page, the previous
              // Upload page, and the Application Process stepper) so Back doesn't
              // re-open the half-done flow — it returns to the root (Dashboard).
              // The already-uploaded docs reload from the server on that screen,
              // so nothing the RM uploaded is lost.
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (_) => UploadDocumentsScreen(
                    lead: widget.lead,
                    stageId: widget.stageId,
                    stageType: widget.stageType,
                  ),
                ),
                (route) => route.isFirst,
              );
            },
            child: const Text('OK',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_error != null && _details == null) {
      // Hard failure before any data → just the retry message.
      body = _ErrorRetry(message: _error!, onRetry: _load);
    } else {
      // Always render the page structure (tabs + labels). While the data is
      // loading, the fields are blank and a translucent loader sits on top.
      body = Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            children: [
              _tabs(),
              const SizedBox(height: 14),
              if (_tab == 0) ..._applicant() else ..._coApplicant(),
            ],
          ),
          if (_loading)
            const Positioned.fill(
              child: AbsorbPointer(
                child: ColoredBox(
                  color: Color(0x66000000),
                  child: Center(
                    child:
                        CircularProgressIndicator(color: AppColors.purple),
                  ),
                ),
              ),
            ),
        ],
      );
    }
    return AppFlowScaffold(
      title: 'Application Details',
      stepText: 'Step 2 of 5',
      bottomBar: InteractionBottomBar(
        actionLabel: _saving ? 'Saving…' : 'Proceed',
        // Shown on the Co-Applicant tab; enabled only when all required fields
        // are filled (mobile numbers, marital/relationship, and the address
        // proof when "same as Aadhar?" is No). See [_canProceed].
        enabled: _tab == 1 && _canProceed && !_saving,
        onAction: _proceed,
      ),
      body: body,
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
    // On No, the current-address data comes from the uploaded proof; with no
    // proof (e.g. just removed) those rows are blank.
    final hasProof = _appProofName != null;
    return [
      FlowCard(
        heading: 'Applicant Details',
        child: Column(
          children: [
            DetailRow(
                label: 'Full Name:',
                sublabel: '(as per PAN)',
                value: a?.fullName ?? ''),
            DetailRow(
                label: 'Mobile Number:',
                valueWidget: _mobileField(_appMobileCtrl)),
            DetailRow(label: 'DOB:', value: _fmtDob(a?.dob ?? '')),
            DetailRow(label: 'Gender:', value: _capFirst(a?.gender ?? '')),
            DetailRow(label: 'Age:', value: a?.ageLabel ?? ''),
            DetailRow(
                label: a?.idNumberLabel ?? 'Aadhar Number:',
                value: a?.idNumber ?? ''),
            DetailRow(label: 'PAN:', value: a?.panNumber ?? ''),
            DetailRow(label: 'Driving License:', value: a?.dlNumber ?? ''),
            DetailRow(label: 'DL Expiry Date:', value: a?.dlValidityDate ?? ''),
            DetailRow(label: 'DL issuing RTO:', value: a?.dlIssueRTO ?? ''),
            DetailRow(
              label: 'Marital Status:',
              valueWidget: _dropdownKeyed(
                value: _maritalStatus,
                items: _maritalItems,
                hint: 'Select Marital Status',
                onChanged: (v) {
                  setState(() => _maritalStatus = v);
                  // Marital status feeds the ownership checksum → refresh the
                  // Residence Type for both applicant + co-applicant (with a
                  // modal loader while the API runs).
                  _runOwnershipChecksumWithLoader();
                },
              ),
            ),
            DetailRow(
                label: 'Address:',
                sublabel: '(as per ${a?.idTypeLabel ?? 'Aadhar'})',
                value: a?.address ?? ''),
            DetailRow(
                label: 'Permanent Address:',
                value: a?.permanentAddressDisplay ?? ''),
          ],
        ),
      ),
      const SizedBox(height: 4),
      _sameAddress(_appSameAddr, (v) => _changeSameAddr(false, v)),
      FlowCard(
        child: Column(
          children: [
            if (!_appSameAddr) ..._addressProof(isCo: false),
            // Yes → the Aadhar address + owner; No → the data from the uploaded
            // proof (upload response, then /details): currAddress, consumerName
            // (→ Owner Name), consumerNumber (→ Bill / Reference Number).
            DetailRow(
                label: 'Current Address:',
                value: _appSameAddr
                    ? (a?.address ?? '')
                    : (hasProof ? (_appCurrAddr ?? a?.currentAddress ?? '') : '')),
            DetailRow(
              label: 'Residence Type:',
              valueWidget: _residenceField(
                // No default — only the checksum response (or a manual pick)
                // selects an option; otherwise the placeholder shows.
                value: _appOwnership ?? '',
                onChanged: (v) => setState(() => _appOwnership = v),
              ),
            ),
            DetailRow(
                label: 'Owner Name:',
                sublabel: '(if not self-owned)',
                // Owner Name = consumerName (uploaded-proof OCR overrides, then
                // the API value) — shown in both Yes/No cases.
                value: _appConsumerName ?? a?.consumerName ?? ''),
            DetailRow(
                label: 'Bill / Reference Number:',
                // = consumerNumber (model: billNumber).
                value: _appConsumerNo ?? a?.billNumber ?? ''),
          ],
        ),
      ),
      const SizedBox(height: 14),
      FlowCard(
        heading: 'Bank Details',
        child: Column(
          children: [
            DetailRow(
                label: 'A/c Holder Name:', value: bank?.accountHolderName ?? ''),
            DetailRow(label: 'Bank Name:', value: bank?.bankName ?? ''),
            DetailRow(label: 'Branch Name:', value: bank?.branchName ?? ''),
            DetailRow(label: 'IFSC Code:', value: bank?.ifscCode ?? ''),
            DetailRow(label: 'Account Type:', value: bank?.accountType ?? ''),
            DetailRow(label: 'Account Number:', value: bank?.accountNumber ?? ''),
          ],
        ),
      ),
    ];
  }

  // ---- Co-Applicant tab ----
  List<Widget> _coApplicant() {
    final c = _details?.coApplicant;
    // On No, the current-address data comes from the uploaded proof; with no
    // proof (e.g. just removed) those rows are blank.
    final hasProof = _coProofName != null;
    return [
      FlowCard(
        heading: 'Co-Applicant Details',
        child: Column(
          children: [
            DetailRow(
                label: 'Full Name:',
                sublabel: '(as per PAN)',
                value: c?.fullName ?? ''),
            DetailRow(
                label: 'Mobile Number:',
                valueWidget: _mobileField(_coMobileCtrl)),
            DetailRow(label: 'DOB:', value: _fmtDob(c?.dob ?? '')),
            DetailRow(label: 'Gender:', value: _capFirst(c?.gender ?? '')),
            DetailRow(label: 'Age:', value: c?.ageLabel ?? ''),
            DetailRow(
                label: c?.idNumberLabel ?? 'Aadhar Number:',
                value: c?.idNumber ?? ''),
            DetailRow(label: 'PAN:', value: c?.panNumber ?? ''),
            DetailRow(
              label: 'Relation with Applicant:',
              valueWidget: _dropdownKeyed(
                value: _relation,
                items: _relationItems,
                hint: 'Select Relationship',
                onChanged: (v) {
                  setState(() => _relation = v);
                  // Relationship feeds the ownership checksum → refresh the
                  // Residence Type for both applicant + co-applicant (with a
                  // modal loader while the API runs).
                  _runOwnershipChecksumWithLoader();
                },
              ),
            ),
            DetailRow(
                label: 'Address:',
                sublabel: '(as per ${c?.idTypeLabel ?? 'Aadhar'})',
                value: c?.address ?? ''),
            DetailRow(
                label: 'Permanent Address:',
                value: c?.permanentAddressDisplay ?? ''),
          ],
        ),
      ),
      const SizedBox(height: 4),
      _sameAddress(_coSameAddr, (v) => _changeSameAddr(true, v)),
      FlowCard(
        child: Column(
          children: [
            if (!_coSameAddr) ..._addressProof(isCo: true),
            // Yes → the Aadhar address + owner; No → the data from the uploaded
            // proof (upload response, then /details): currAddress, consumerName
            // (→ Owner Name), consumerNumber (→ Bill / Reference Number).
            DetailRow(
                label: 'Current Address:',
                value: _coSameAddr
                    ? (c?.address ?? '')
                    : (hasProof ? (_coCurrAddr ?? c?.currentAddress ?? '') : '')),
            DetailRow(
              label: 'Residence Type:',
              valueWidget: _residenceField(
                // No default — only the checksum response (or a manual pick)
                // selects an option; otherwise the placeholder shows.
                value: _coOwnership ?? '',
                onChanged: (v) => setState(() => _coOwnership = v),
              ),
            ),
            DetailRow(
                label: 'Owner Name:',
                sublabel: '(if not self-owned)',
                // Owner Name = consumerName (uploaded-proof OCR overrides, then
                // the API value) — shown in both Yes/No cases.
                value: _coConsumerName ?? c?.consumerName ?? ''),
            DetailRow(
                label: 'Bill / Reference Number:',
                // = consumerNumber (model: billNumber).
                value: _coConsumerNo ?? c?.billNumber ?? ''),
          ],
        ),
      ),
    ];
  }

  // Toggle the "same as Aadhar address?" radio. Switching No → Yes when a
  // current-address proof was uploaded asks first — Yes removes the proof
  // (server delete + clear) then switches; No keeps the current selection.
  Future<void> _changeSameAddr(bool isCo, bool value) async {
    final current = isCo ? _coSameAddr : _appSameAddr;
    if (value == current) return;
    final hasProof = (isCo ? _coProofName : _appProofName) != null;
    // Only the No → Yes direction with an uploaded proof needs confirmation.
    if (value == true && hasProof) {
      final ok = await _confirmRemoveProof();
      if (!ok || !mounted) return; // stay on No
      await _removeProof(isCo); // delete on the server + clear locally
      if (!mounted) return;
    }
    setState(() {
      if (isCo) {
        _coSameAddr = value;
      } else {
        _appSameAddr = value;
      }
    });
    if (value == true) {
      // YES: current address = Aadhar → derive Residence Type from the API's
      // owner name right away.
      _runOwnershipChecksum();
    } else {
      // NO: owner name comes from the proof OCR (not uploaded yet) → drop the
      // derived Residence Type until the proof is uploaded.
      setState(() => isCo ? _coOwnership = null : _appOwnership = null);
    }
  }

  // Confirm before dropping an uploaded current-address proof on No → Yes.
  Future<bool> _confirmRemoveProof() async {
    final p = context.palette;
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Remove uploaded proof?',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: p.title)),
        content: Text(
          'If you select "Yes", your uploaded current address proof will be '
          'removed.',
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

  // "Is the current address same as the Aadhar address?" Yes / No.
  Widget _sameAddress(bool value, ValueChanged<bool> onChanged) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Is the current address same as the Aadhar address?',
            style: TextStyle(fontSize: 13.5, color: p.subtitle),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _radio('Yes', value == true, () => onChanged(true)),
              const SizedBox(width: 24),
              _radio('No', value == false, () => onChanged(false)),
            ],
          ),
        ],
      ),
    );
  }

  // Shown only when "No": Current Address Proof dropdown + allowed-types hint +
  // Upload (CURRENT_ADDRESS_PROOF / CO_CURRENT_ADDRESS_PROOF on the upload API).
  List<Widget> _addressProof({required bool isCo}) {
    final proof = isCo ? _coProof : _appProof;
    return [
      DetailRow(
        label: 'Current Address Proof:',
        valueWidget: _dropdownKeyed(
          value: proof,
          items: _proofItems,
          hint: 'Select Address Proof',
          onChanged: (v) =>
              setState(() => isCo ? _coProof = v : _appProof = v),
        ),
      ),
      DetailRow(
        label: 'Current Address Proof:',
        valueWidget: _proofUploadField(isCo),
      ),
    ];
  }

  // Address-proof upload UI — mirrors the Upload Documents screen: an Upload
  // button (sheet → file/camera, image crop) and, once uploaded, a tappable
  // thumbnail + file name + a Remove (X) button.
  Widget _proofUploadField(bool isCo) {
    final name = isCo ? _coProofName : _appProofName;
    final path = isCo ? _coProofPath : _appProofPath;
    final preview = isCo ? _coProofPreview : _appProofPreview;
    final uploading = isCo ? _uploadingCo : _uploadingApp;
    final removing = isCo ? _removingCo : _removingApp;
    // Uploading → no file yet, show a full loader where the Upload button was.
    if (uploading) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
              strokeWidth: 2.4, color: AppColors.primary),
        ),
      );
    }
    if (name == null) {
      // Upload stays disabled until a proof TYPE is chosen from the dropdown.
      final typeSelected = (isCo ? _coProof : _appProof).isNotEmpty;
      final color = typeSelected ? AppColors.primary : Colors.grey;
      return Align(
        alignment: Alignment.centerLeft,
        child: Opacity(
          opacity: typeSelected ? 1 : 0.5,
          child: GestureDetector(
            onTap: typeSelected ? () => _showProofSheet(isCo) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color),
              ),
              child: Text('Upload',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: color)),
            ),
          ),
        ),
      );
    }
    final isPdf = path != null && path.toLowerCase().endsWith('.pdf');
    final serverId = isCo ? _coProofId : _appProofId;
    // Thumbnail: fresh local image → file; else a previously-uploaded server
    // doc → small thumbnail (full file fetched on tap via /application/document);
    // else a PDF/doc icon.
    final Widget thumb;
    if (path != null && !isPdf) {
      thumb = GestureDetector(
        onTap: () => _previewProofImage(path),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(File(path), width: 38, height: 38, fit: BoxFit.cover),
        ),
      );
    } else if (path == null && serverId != null && serverId.isNotEmpty) {
      // Server proof — tap to load & view the full file. Shows the small
      // thumbnail when present, a generic image icon otherwise.
      thumb = GestureDetector(
        onTap: () => _viewServerProof(isCo),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: DocThumbImage(
            url: isCo ? _coProofUrl : _appProofUrl,
            bytes: preview,
            width: 38,
            height: 38,
            fit: BoxFit.cover,
            placeholder: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.purple.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.image_outlined,
                  size: 20, color: context.palette.iconGrey),
            ),
          ),
        ),
      );
    } else {
      thumb = GestureDetector(
        onTap: () => path != null && isPdf ? _previewProofPdf(path) : null,
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.statusRed.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.picture_as_pdf,
              size: 20, color: AppColors.statusRed),
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        thumb,
        const SizedBox(width: 8),
        const Icon(Icons.check_circle, size: 18, color: AppColors.success),
        const SizedBox(width: 4),
        Expanded(
          child: Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.success)),
        ),
        const SizedBox(width: 6),
        // While removing, the file stays visible and the X turns into a small
        // loader — it's only cleared once the server confirms success.
        removing
            ? const SizedBox(
                width: 26,
                height: 26,
                child: Padding(
                  padding: EdgeInsets.all(5),
                  child: CircularProgressIndicator(
                      strokeWidth: 2.2, color: AppColors.statusRed),
                ),
              )
            : GestureDetector(
                onTap: () => _removeProof(isCo),
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
      ],
    );
  }

  //Property Tax, Gas Bill, Electricity Bill, Bank Statement
  // Tapping Upload opens a sheet: pick a file (PDF/image) OR capture from camera.
  Future<void> _showProofSheet(bool isCo) async {
    // The proof TYPE must be chosen first (it's sent with the file as
    // proof_Type / co_proof_Type).
    if ((isCo ? _coProof : _appProof).isEmpty) {
      _snack('Please select the address proof type first');
      return;
    }
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
      await _pickProofFile(isCo);
    } else if (choice == 'camera') {
      await _captureProof(isCo);
    }
  }

  Future<void> _pickProofFile(bool isCo) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _allowedExt,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final f = result.files.first;
      final ext = (f.extension ?? '').toLowerCase();
      if (!_allowedExt.contains(ext)) {
        _snack('Sirf PDF ya image (png/jpg/jpeg) upload ho sakti hai');
        return;
      }
      if (f.path == null) {
        _snack('File select nahi hui, dobara try karein');
        return;
      }
      if (ext == 'pdf' && f.size > _maxUploadBytes) {
        _snack('Please upload PDF 10 MB or below');
        return;
      }
      await _onProofPicked(isCo, f.path!, f.name, ext);
    } catch (_) {
      _snack('File select nahi hui, dobara try karein');
    }
  }

  Future<void> _captureProof(bool isCo) async {
    try {
      final img = await ImagePicker().pickImage(source: ImageSource.camera);
      if (img == null) return;
      final ext = img.name.contains('.')
          ? img.name.split('.').last.toLowerCase()
          : 'jpg';
      await _onProofPicked(isCo, img.path, img.name, ext);
    } catch (_) {
      _snack('Camera nahi khula, dobara try karein');
    }
  }

  // Images are cropped first; the 10 MB cap is enforced on the result. PDFs go
  // straight to upload.
  Future<void> _onProofPicked(
      bool isCo, String path, String name, String ext) async {
    final isImage = ext == 'png' || ext == 'jpg' || ext == 'jpeg';
    var usePath = path;
    var useName = name;
    if (isImage) {
      final cropped = await _cropProofImage(path);
      if (cropped == null) return; // cancelled
      usePath = cropped;
      useName = cropped.split(Platform.pathSeparator).last;
      final size = await File(cropped).length();
      if (size > _maxUploadBytes) {
        _snack('Please upload image 10 MB or below');
        return;
      }
      if (!mounted) return;
    }
    await _uploadProof(isCo, usePath, useName);
  }

  Future<String?> _cropProofImage(String path) async {
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

  // Upload the picked/cropped proof to the server (CURRENT_ADDRESS_PROOF /
  // CO_CURRENT_ADDRESS_PROOF). On success keep the local path for the thumbnail.
  Future<void> _uploadProof(bool isCo, String path, String name) async {
    final field = isCo ? 'CO_CURRENT_ADDRESS_PROOF' : 'CURRENT_ADDRESS_PROOF';
    // Send the selected proof type's key along with the file:
    //  applicant → proof_Type, co-applicant → co_proof_Type.
    final typeField = isCo ? 'co_proof_Type' : 'proof_Type';
    final typeKey = isCo ? _coProof : _appProof; // already the API value(key)
    setState(() => isCo ? _uploadingCo = true : _uploadingApp = true);
    try {
      final res = await _appRepo.uploadFiles(
        leadId: widget.lead.id,
        files: {field: path},
        fields: {typeField: typeKey},
      );
      if (!mounted) return;
      final ok = res is Map && (res['success'] == true || res['status'] == true);
      final msg = (res is Map &&
              res['message'] is String &&
              (res['message'] as String).trim().isNotEmpty)
          ? (res['message'] as String).trim()
          : (ok ? 'Address proof uploaded' : 'Upload failed');
      _snack(msg, ok: ok);
      if (ok) {
        // Pull currAddress / consumerName / consumerNumber out of the response
        // (tolerate a `data` wrapper) so the fields fill in instantly.
        final Map data = res['data'] is Map ? res['data'] as Map : res;
        String? g(String k) {
          final v = data[k];
          return (v == null || v.toString().trim().isEmpty)
              ? null
              : v.toString();
        }

        setState(() {
          if (isCo) {
            _coProofName = name;
            _coProofPath = path;
            _coProofPreview = null; // fresh local file → use the path
            _coProofUrl = '';
            _coProofId = null;
            _coCurrAddr = g('currAddress');
            _coConsumerName = g('consumerName');
            _coConsumerNo = g('consumerNumber');
          } else {
            _appProofName = name;
            _appProofPath = path;
            _appProofPreview = null;
            _appProofUrl = '';
            _appProofId = null;
            _appCurrAddr = g('currAddress');
            _appConsumerName = g('consumerName');
            _appConsumerNo = g('consumerNumber');
          }
        });
        // Re-fetch details too so a returning user sees the same data from
        // /details.
        await _refreshDetails();
        // The proof's OCR owner name (consumerName) is now available → derive
        // the Residence Type from it.
        await _runOwnershipChecksum();
      }
    } on ApiException catch (e) {
      if (mounted) _snack(e.message);
    } catch (_) {
      if (mounted) _snack('Something went wrong. Please try again.');
    } finally {
      if (mounted) {
        setState(() => isCo ? _uploadingCo = false : _uploadingApp = false);
      }
    }
  }

  // Remove the uploaded proof from the server, then clear it locally.
  Future<void> _removeProof(bool isCo) async {
    final field = isCo ? 'CO_CURRENT_ADDRESS_PROOF' : 'CURRENT_ADDRESS_PROOF';
    setState(() => isCo ? _removingCo = true : _removingApp = true);
    try {
      final res =
          await _appRepo.deleteDocument(leadId: widget.lead.id, docCode: field);
      if (!mounted) return;
      final ok = res is Map && (res['success'] == true || res['status'] == true);
      final msg = (res is Map &&
              res['message'] is String &&
              (res['message'] as String).trim().isNotEmpty)
          ? (res['message'] as String).trim()
          : (ok ? 'Document removed successfully' : 'Could not delete document');
      if (!ok) {
        _snack(msg); // red error
        return;
      }
      // Only NOW (server confirmed success) clear the file + its No-flow data.
      setState(() {
        if (isCo) {
          _coProofName = null;
          _coProofPath = null;
          _coProofPreview = null;
          _coProofUrl = '';
          _coProofId = null;
          _coCurrAddr = null;
          _coConsumerName = null;
          _coConsumerNo = null;
          // Owner name is gone → drop the derived Residence Type too.
          _coOwnership = null;
        } else {
          _appProofName = null;
          _appProofPath = null;
          _appProofPreview = null;
          _appProofUrl = '';
          _appProofId = null;
          _appCurrAddr = null;
          _appConsumerName = null;
          _appConsumerNo = null;
          _appOwnership = null;
        }
      });
      _snack(msg, ok: true); // green success (server message)
      // Re-fetch so the now-removed proof's current address clears too.
      await _refreshDetails();
    } on ApiException catch (e) {
      if (mounted) _snack(e.message);
    } catch (_) {
      if (mounted) _snack('Something went wrong. Please try again.');
    } finally {
      if (mounted) {
        setState(() => isCo ? _removingCo = false : _removingApp = false);
      }
    }
  }

  // View a previously-uploaded (server) Current Address proof. The details list
  // now carries only a small thumbnail, so the full file is fetched on demand
  // (POST /application/document) and then shown (image / PDF).
  Future<void> _viewServerProof(bool isCo) async {
    final id = isCo ? _coProofId : _appProofId;
    if (id == null || id.isEmpty) return;
    final type = isCo ? 'CO_APPLICANT' : 'APPLICANT';
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );
    DocumentFile? file;
    try {
      file =
          await _appRepo.getDocumentFile(documentId: id, applicantType: type);
    } on ApiException catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        _snack(e.message);
      }
      return;
    } catch (_) {
      if (mounted) {
        Navigator.of(context).pop();
        _snack('Something went wrong. Please try again.');
      }
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(); // close loader
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      _snack('Preview not available for this document.');
      return;
    }
    if (file.isPdf) {
      try {
        final name = file.fileName.isNotEmpty ? file.fileName : 'document.pdf';
        final f = File('${Directory.systemTemp.path}/$name');
        await f.writeAsBytes(bytes, flush: true);
        if (!mounted) return;
        _previewProofPdf(f.path);
      } catch (_) {
        if (mounted) _snack('Could not open this PDF.');
      }
    } else {
      _previewProofMemory(bytes);
    }
  }

  // Full-size preview of a proof image (from fetched full bytes).
  void _previewProofMemory(Uint8List bytes) {
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

  // Full-size image preview (tapped thumbnail).
  void _previewProofImage(String path) {
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

  // Full-screen PDF preview (tapped PDF thumbnail).
  void _previewProofPdf(String path) {
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _ProofPdfViewer(path: path),
    ));
  }

  void _snack(String msg, {bool ok = false}) {
    AppToast.show(context, msg,
        type: ok ? ToastType.success : ToastType.error);
  }

  Widget _radio(String label, bool selected, VoidCallback onTap) {
    final p = context.palette;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            size: 20,
            color: selected ? AppColors.purple : p.iconGrey,
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 14, color: p.title)),
        ],
      ),
    );
  }

  // Residence Type field: while the /location/checksum call is running it shows
  // an inline loader (so it's clear the API is working); otherwise the 3-option
  // dropdown (pre-selected from the response, or pickable manually).
  Widget _residenceField({
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    final p = context.palette;
    if (_checkingOwnership) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: p.fieldBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: p.fieldBorder),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text('Checking…',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w500, color: p.hint)),
          ],
        ),
      );
    }
    return _dropdownKeyed(
      value: value,
      items: _residenceItems,
      hint: 'Select Residence Type',
      onChanged: onChanged,
    );
  }

  // Dropdown whose VALUE (key) differs from its shown LABEL — used for marital
  // status so the stored/sent value stays lowercase while the label is capital.
  Widget _dropdownKeyed({
    required String value,
    required Map<String, String> items, // key -> label
    required ValueChanged<String> onChanged,
    String? hint, // placeholder shown when nothing is selected
  }) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: p.fieldBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.fieldBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          // null when the value isn't a valid option → shows the [hint].
          value: items.containsKey(value) ? value : null,
          hint: hint == null
              ? null
              : Text(hint,
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500, color: p.hint)),
          isExpanded: true,
          isDense: true,
          icon: Icon(Icons.keyboard_arrow_down, color: p.subtitle),
          dropdownColor: p.cardBg,
          style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600, color: p.title),
          padding: const EdgeInsets.symmetric(vertical: 12),
          items: [
            for (final e in items.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) => onChanged(v ?? value),
        ),
      ),
    );
  }

  // Editable, bordered mobile-number field (10-digit numeric).
  Widget _mobileField(TextEditingController controller) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: p.fieldBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.fieldBorder),
      ),
      child: TextField(
        controller: controller,
        // Prefilled + editable, but the keyboard must NOT pop up on page load —
        // it opens only when the RM taps the field. autofocus:false is the
        // default; kept explicit so this stays true for applicant & co-applicant.
        autofocus: false,
        keyboardType: TextInputType.phone,
        maxLength: 10,
        // Digits only — so the 10-char limit is 10 real digits.
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w600, color: p.title),
        decoration: InputDecoration(
          counterText: '',
          isDense: true,
          border: InputBorder.none,
          hintText: 'Enter mobile number',
          hintStyle: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w500, color: p.hint),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

}

/// Centered error message + Retry.
class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: p.subtitle)),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

/// Full-screen PDF viewer for a tapped address-proof PDF thumbnail.
class _ProofPdfViewer extends StatefulWidget {
  const _ProofPdfViewer({required this.path});
  final String path;

  @override
  State<_ProofPdfViewer> createState() => _ProofPdfViewerState();
}

class _ProofPdfViewerState extends State<_ProofPdfViewer> {
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
