import 'package:flutter/material.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/local/application_stage_store.dart';
import '../../data/models/lead_item.dart';
import '../../data/models/lead_preview.dart';
import '../../data/models/person_detail.dart';
import '../../data/repositories/application_repository.dart';
import '../../data/repositories/lead_repository.dart';
import '../../theme/app_colors.dart';
import '../widgets/interaction_ui.dart';
import 'application_flow_ui.dart';
import 'submit_application_screen.dart';

/// Step 4 of 5 — KYC Verification. Driven by `/application/details`
/// (`docsVerifications[]`): each document shows its status —
/// Success → Verified (green), Pending → Pending (amber), Failed → Failed (red).
class KycVerificationScreen extends StatefulWidget {
  const KycVerificationScreen({super.key, required this.lead});
  final LeadItem lead;

  @override
  State<KycVerificationScreen> createState() => _KycVerificationScreenState();
}

class _KycVerificationScreenState extends State<KycVerificationScreen> {
  final ApplicationRepository _repo = ApplicationRepository();
  bool _loading = true;
  bool _proceeding = false; // save-verification call in progress
  String? _error;
  List<DocVerification> _docs = const [];
  String _applicationId = ''; // from /application/details (for save-verification)
  ApplicationDetails? _details; // full details — for each doc's number sub-line

  // Bank Passbook / PAN / Aadhaar rows must each be verified via their own
  // endpoint before Proceed is enabled — they don't trust the server's status,
  // the row must be verified (automatically on load, or via its Verify button).
  final Set<String> _verified = {}; // keys of locally-verified rows
  String? _verifyingKey; // row key whose verify call is in flight

  // Unique key for a doc row (type + code) — used to track verification.
  String _docKey(DocVerification d) => '${d.applicantType}|${d.documentCode}';

  // The document code without the co-applicant CO_ prefix.
  String _bareCode(DocVerification d) =>
      d.documentCode.trim().toUpperCase().replaceFirst('CO_', '');

  bool _isPassbook(DocVerification d) => _bareCode(d) == 'PASSBOOK';
  bool _isPan(DocVerification d) => _bareCode(d) == 'PAN';
  bool _isAadhaar(DocVerification d) => _bareCode(d) == 'AADHAAR';

  // Rows that carry a Verify button and gate Proceed.
  bool _isVerifiable(DocVerification d) =>
      _isPassbook(d) || _isPan(d) || _isAadhaar(d);

  // Proceed is allowed only once EVERY verifiable row has been verified locally.
  bool get _allVerified {
    for (final d in _docs) {
      if (_isVerifiable(d) && !_verified.contains(_docKey(d))) return false;
    }
    return true;
  }

  // applicantType as the pan/aadhaar-verification endpoints expect it.
  String _partyType(DocVerification d) =>
      d.isApplicant ? 'APPLICANT' : 'CO_APPLICANT';

  // application_id as an int when it parses, else the raw string.
  dynamic get _appIdParam =>
      int.tryParse(_applicationId.trim()) ?? _applicationId;

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
      debugPrint('KYC docsVerifications: ${d.docsVerifications.length} '
          '(leadId: ${widget.lead.id}, appId: ${d.applicationId})');
      if (!mounted) return;
      setState(() {
        _details = d;
        _docs = d.docsVerifications;
        _applicationId = d.applicationId;
        _loading = false;
      });
      // Run verification automatically as soon as the page loads — no need for
      // the user to tap Verify on each Passbook / PAN / Aadhaar row.
      _autoVerifyDocs();
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
    return AppFlowScaffold(
      lockBack: true, // post-OTP — no going back to an earlier step
      title: 'KYC Verification',
      stepText: 'Step 4 of 5',
      bottomBar: InteractionBottomBar(
        actionLabel: _proceeding ? 'Saving…' : 'Proceed',
        enabled: !_proceeding && !_loading && _allVerified,
        onAction: _onProceed,
      ),
      body: _body(),
    );
  }

  // Proceed → save-verification (docs + stage from KYC Verification), then the
  // Submit Application screen on success.
  Future<void> _onProceed() async {
    if (_proceeding) return;
    setState(() => _proceeding = true);
    try {
      final appId = int.tryParse(_applicationId.trim()) ?? _applicationId;
      final leadId = int.tryParse(widget.lead.id.trim()) ?? widget.lead.id;
      final stage = await _resolveKycStage();
      final docs = _docs
          .map((d) => {
                'applicantType': _normalizeType(d.applicantType),
                'documentCode': d.documentCode,
              })
          .toList();
      debugPrint('save-verification → stage:${stage.id}/${stage.type} '
          'docs:${docs.length}');
      final res = await _repo.saveVerification(
        applicationId: appId,
        leadId: leadId,
        stageId: stage.id,
        stageType: stage.type,
        docsVerifications: docs,
      );
      if (!mounted) return;
      final ok = res is Map && (res['success'] == true || res['status'] == true);
      final msg = (res is Map &&
              res['message'] is String &&
              (res['message'] as String).trim().isNotEmpty)
          ? (res['message'] as String).trim()
          : null;
      if (!ok) {
        _snack(msg ?? 'Could not save verification. Please try again.');
        return;
      }
      if (msg != null) _snack(msg, ok: true);
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SubmitApplicationScreen(lead: widget.lead),
      ));
    } on ApiException catch (e) {
      if (mounted) _snack(e.message);
    } catch (_) {
      if (mounted) _snack('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _proceeding = false);
    }
  }

  // applicantType normalised to the save-verification shape (CO_APPLICANT).
  String _normalizeType(String t) {
    final u = t.trim().toUpperCase();
    return (u == 'COAPPLICANT' || u == 'CO_APPLICANT') ? 'CO_APPLICANT' : 'APPLICANT';
  }

  // KYC Verification stage id + type: SharedPreferences (saved from getPreview)
  // → a fresh getPreview (cache it) → empty.
  Future<({String id, String type})> _resolveKycStage() async {
    StageItem? saved = await ApplicationStageStore.instance
        .stageByName(widget.lead.id, 'KYC Verification');
    if (saved == null || saved.id.isEmpty) {
      try {
        final preview = await LeadRepository().getPreview(leadId: widget.lead.id);
        await ApplicationStageStore.instance
            .save(widget.lead.id, preview.applicationStages);
        for (final s in preview.applicationStages) {
          if (s.stageName.trim().toLowerCase() == 'kyc verification') {
            saved = s;
            break;
          }
        }
      } catch (_) {/* ignore */}
    }
    return (id: saved?.id ?? '', type: saved?.stageType ?? '');
  }

  void _snack(String msg, {bool ok = false}) {
    AppToast.show(context, msg,
        type: ok ? ToastType.success : ToastType.error);
  }

  // Verify every un-verified Bank Passbook / PAN / Aadhaar row automatically
  // (called on page load). Runs sequentially so each row's spinner shows in
  // turn; the success toast is suppressed to avoid one toast per row.
  Future<void> _autoVerifyDocs() async {
    for (final d in _docs) {
      if (!mounted) return;
      if (_isVerifiable(d) && !_verified.contains(_docKey(d))) {
        await _onVerify(d, auto: true);
      }
    }
  }

  // Verify one row against its own endpoint, marking it Verified (and so
  // enabling Proceed) only on a success response. Each row's identifiers come
  // from /application/details.
  Future<void> _onVerify(DocVerification d, {bool auto = false}) async {
    if (_verifyingKey != null) return; // one verify at a time
    final key = _docKey(d);
    setState(() => _verifyingKey = key);
    try {
      final ({bool skip, dynamic res, String failMsg, String okMsg})? outcome =
          await _callVerify(d);
      if (!mounted || outcome == null) return; // null → missing data, toasted
      if (outcome.skip) {
        setState(() => _verified.add(key));
        return;
      }
      final res = outcome.res;
      debugPrint('verify ${d.documentCode} (${_partyType(d)}) → $res');
      final ok = _isVerifySuccess(res);
      final msg = (res is Map &&
              res['message'] is String &&
              (res['message'] as String).trim().isNotEmpty)
          ? (res['message'] as String).trim()
          : null;
      if (ok) {
        setState(() => _verified.add(key));
        if (!auto) _snack(msg ?? outcome.okMsg, ok: true);
      } else {
        _snack(msg ?? outcome.failMsg);
      }
    } on ApiException catch (e) {
      if (mounted) _snack(e.message);
    } catch (_) {
      if (mounted) _snack('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _verifyingKey = null);
    }
  }

  // Dispatch a row to its endpoint. Returns null (after toasting) when the
  // identifier this row needs is missing from /application/details. `skip: true`
  // means the server already verified it and no call was made.
  Future<({bool skip, dynamic res, String failMsg, String okMsg})?> _callVerify(
      DocVerification d) async {
    final person = d.isApplicant ? _details?.applicant : _details?.coApplicant;

    if (_isPassbook(d)) {
      final bank = _details?.bankDetails;
      // Already verified on the server → mark Verified WITHOUT calling
      // /bank-verification, so the RM can proceed straight away.
      if (bank?.isVerified == true) {
        return (skip: true, res: null, failMsg: '', okMsg: '');
      }
      final account = (bank?.accountNumber ?? '').trim();
      if (account.isEmpty) {
        _snack('Bank account number not found for this applicant.');
        return null;
      }
      final res = await _repo.verifyBank(
        applicationId: _appIdParam,
        accountNumber: account,
        ifsc: (bank?.ifscCode ?? '').trim(),
      );
      return (
        skip: false,
        res: res,
        failMsg: 'Bank verification failed. Please try again.',
        okMsg: 'Bank account verified successfully.',
      );
    }

    if (_isPan(d)) {
      // Already verified on the server (`applicant.pan_verified`) → mark
      // Verified WITHOUT calling /pan-verification.
      if (person?.panVerified == true) {
        return (skip: true, res: null, failMsg: '', okMsg: '');
      }
      final pan = (person?.panNumber ?? '').trim();
      final name = (person?.fullName ?? '').trim();
      final dob = (person?.dob ?? '').trim();
      if (pan.isEmpty) {
        _snack('PAN number not found for this applicant.');
        return null;
      }
      final res = await _repo.verifyPan(
        applicationId: _appIdParam,
        applicantType: _partyType(d),
        panNumber: pan,
        fullName: name,
        dob: dob,
      );
      return (
        skip: false,
        res: res,
        failMsg: 'PAN verification failed. Please try again.',
        okMsg: 'PAN verified successfully.',
      );
    }

    // Aadhaar. Already verified on the server (`applicant.aadhar_verified`) →
    // mark Verified WITHOUT calling /aadhaar-verification.
    if (person?.aadhaarVerified == true) {
      return (skip: true, res: null, failMsg: '', okMsg: '');
    }
    final aadhaar = (person?.aadhaarNumber ?? '').trim();
    if (aadhaar.isEmpty) {
      _snack('Aadhaar number not found for this applicant.');
      return null;
    }
    final res = await _repo.verifyAadhaar(
      applicationId: _appIdParam,
      applicantType: _partyType(d),
      aadhaarNumber: aadhaar,
    );
    return (
      skip: false,
      res: res,
      failMsg: 'Aadhaar verification failed. Please try again.',
      okMsg: 'Aadhaar verified successfully.',
    );
  }

  // Bank-verification success: a truthy success/status/valid/verified flag.
  bool _isVerifySuccess(dynamic res) {
    if (res is! Map) return false;
    for (final k in const ['success', 'status', 'valid', 'verified']) {
      final v = res[k];
      if (v == true) return true;
      if (v is String) {
        final s = v.trim().toLowerCase();
        if (s == 'true' || s == 'success' || s == 'valid' || s == 'verified') {
          return true;
        }
      }
    }
    return false;
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        const SizedBox(height: 6),
        Center(
          child: Text('Document Verification',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, color: p.title)),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text('Verification status of the uploaded documents',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: p.subtitle)),
        ),
        const SizedBox(height: 18),
        if (_docs.isEmpty)
          FlowCard(
            child: Text('No documents found.',
                style: TextStyle(fontSize: 14, color: p.subtitle)),
          )
        else
          FlowCard(
            child: Column(
              children: [
                for (var i = 0; i < _docs.length; i++) ...[
                  _docRow(context, _docs[i]),
                  if (i != _docs.length - 1) const SizedBox(height: 10),
                ],
              ],
            ),
          ),
      ],
    );
  }

  // Status → label + colour + icon.
  ({String label, Color color, IconData icon}) _statusUi(String s) {
    switch (s.trim().toLowerCase()) {
      case 'success':
        return (
          label: 'Verified',
          color: AppColors.success,
          icon: Icons.check_circle
        );
      case 'failed':
        return (
          label: 'Failed',
          color: AppColors.statusRed,
          icon: Icons.cancel
        );
      case 'pending':
      default:
        return (
          label: 'Pending',
          color: AppColors.deepOrange,
          icon: Icons.schedule
        );
    }
  }

  // Readable document name from its code (strips the CO_ prefix).
  String _docLabel(String code) {
    final c = code.trim().toUpperCase().replaceFirst('CO_', '');
    switch (c) {
      case 'AADHAAR':
        return 'Aadhaar Card';
      case 'PAN':
        return 'PAN Card';
      case 'DRIVING_LICENCE':
      case 'DRIVING_LICENSE':
        return 'Driving License';
      case 'PASSBOOK':
        return 'Bank Passbook';
      case 'ADDRESS_PROOF':
        return 'Address Proof';
      case 'CURRENT_ADDRESS_PROOF':
        return 'Current Address Proof';
      case 'VOTER_ID':
        return 'Voter ID';
      default:
        return c
            .split('_')
            .where((w) => w.isNotEmpty)
            .map((w) => '${w[0]}${w.substring(1).toLowerCase()}')
            .join(' ');
    }
  }

  // The document number for a row, taken from /application/details and masked
  // (applicant vs co-applicant chosen by the row's type). Empty → no sub-line.
  String _docNumber(DocVerification d) {
    final person = d.isApplicant ? _details?.applicant : _details?.coApplicant;
    final code = d.documentCode.trim().toUpperCase().replaceFirst('CO_', '');
    switch (code) {
      case 'AADHAAR':
        return _maskTail(person?.aadhaarNumber ?? '', group: 4);
      case 'PAN':
        return _maskPan(person?.panNumber ?? '');
      case 'DRIVING_LICENCE':
      case 'DRIVING_LICENSE':
        return _maskTail(person?.dlNumber ?? '');
      case 'VOTER_ID':
        return _maskTail(person?.voterIdNumber ?? '');
      case 'PASSBOOK':
      case 'BANK':
      case 'BANK_ACCOUNT':
      case 'ACCOUNT':
        return _maskTail(_details?.bankDetails?.accountNumber ?? '');
      default:
        return '';
    }
  }

  // Keep the last [visible] chars, mask the rest with X. Optionally group into
  // blocks of [group] separated by spaces (e.g. "XXXX XXXX 3855").
  String _maskTail(String raw, {int visible = 4, int? group}) {
    final v = raw.trim();
    if (v.isEmpty || v.length <= visible) return v;
    final masked =
        'X' * (v.length - visible) + v.substring(v.length - visible);
    if (group == null) return masked;
    final buf = StringBuffer();
    for (var i = 0; i < masked.length; i++) {
      if (i > 0 && i % group == 0) buf.write(' ');
      buf.write(masked[i]);
    }
    return buf.toString();
  }

  // PAN AAAAA9999A → first 5 + XXXX + last char (e.g. "BZEPTXXXXP").
  String _maskPan(String raw) {
    final v = raw.trim().toUpperCase();
    if (v.length < 10) return v;
    return '${v.substring(0, 5)}XXXX${v.substring(9)}';
  }

  Widget _docRow(BuildContext context, DocVerification d) {
    final p = context.palette;
    final ui = _statusUi(d.verificationStatus);
    final who = d.isApplicant ? 'Applicant' : 'Co-Applicant';
    final number = _docNumber(d);
    // Passbook / PAN / Aadhaar rows: stay un-verified (showing a Verify button)
    // until verified against their own endpoint.
    final verifiable = _isVerifiable(d);
    final done = verifiable && _verified.contains(_docKey(d));
    final leadIcon =
        verifiable ? (done ? Icons.check_circle : _pendingIcon(d)) : ui.icon;
    final leadColor =
        verifiable ? (done ? AppColors.success : p.subtitle) : ui.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: p.fieldBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.fieldBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(leadIcon, size: 22, color: leadColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: _docLabel(d.documentCode),
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: p.title),
                      ),
                      TextSpan(
                        text: '  ($who)',
                        style: TextStyle(fontSize: 12.5, color: p.subtitle),
                      ),
                    ],
                  ),
                ),
                // Document number sub-line (from /application/details).
                if (number.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(number,
                      style: TextStyle(
                          fontSize: 12.5,
                          letterSpacing: 0.4,
                          color: p.subtitle)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (verifiable && !done)
            _verifyButton(d)
          else
            Text(verifiable ? 'Verified' : ui.label,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: verifiable ? AppColors.success : ui.color)),
        ],
      ),
    );
  }

  // Leading icon for an un-verified verifiable row.
  IconData _pendingIcon(DocVerification d) {
    if (_isPassbook(d)) return Icons.account_balance_outlined;
    if (_isPan(d)) return Icons.credit_card_outlined;
    return Icons.badge_outlined; // Aadhaar
  }

  // Small "Verify" button shown on an un-verified Passbook / PAN / Aadhaar row;
  // spins while its verification call is in flight and is disabled when another
  // row's verification is running.
  Widget _verifyButton(DocVerification d) {
    final verifying = _verifyingKey == _docKey(d);
    final disabled = _verifyingKey != null;
    return SizedBox(
      height: 32,
      child: ElevatedButton(
        onPressed: disabled ? null : () => _onVerify(d),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
          disabledForegroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: verifying
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Text('Verify',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
