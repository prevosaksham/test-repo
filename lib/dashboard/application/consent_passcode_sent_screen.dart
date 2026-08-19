import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/models/lead_item.dart';
import '../../data/repositories/application_repository.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_colors.dart';
import '../widgets/interaction_ui.dart';
import 'application_flow_ui.dart';
import 'consent_captured_screen.dart';

/// Step 3 of 5 (OTP mode) — shown after the Send OTP call succeeds. The
/// send-otp call delivers a passcode to BOTH the applicant and the co-applicant,
/// so this screen shows both numbers and a 4-digit passcode entry for each.
/// Verify OTP advances to Consent Captured.
class ConsentPasscodeSentScreen extends StatefulWidget {
  const ConsentPasscodeSentScreen({
    super.key,
    required this.lead,
    this.isCoApplicant = false,
    this.applicationId = '',
    this.applicationNo = '',
    this.applicantMobile = '',
    this.coApplicantMobile = '',
    this.consentIds = const [],
    this.message = '',
  });
  final LeadItem lead;
  final bool isCoApplicant;
  final String applicationId; // data.application.id — the send-otp app id
  final String applicationNo;
  final String applicantMobile;
  final String coApplicantMobile;
  final List<int> consentIds; // all consent item ids (for Resend)
  final String message; // server message from send-otp ("" → static fallback)

  @override
  State<ConsentPasscodeSentScreen> createState() =>
      _ConsentPasscodeSentScreenState();
}

class _ConsentPasscodeSentScreenState extends State<ConsentPasscodeSentScreen> {
  final ApplicationRepository _repo = ApplicationRepository();

  static const int _resendSeconds = 45;
  // Independent resend state per person — applicant & co-applicant resend
  // separately (apna OTP, apna countdown, apna loader).
  Timer? _appTimer;
  Timer? _coTimer;
  int _appLeft = _resendSeconds;
  int _coLeft = _resendSeconds;
  bool _appResending = false;
  bool _coResending = false;
  bool _verifying = false; // Verify OTP call in progress

  // Two 6-digit passcodes: applicant + co-applicant.
  static const int _otpLen = 6;
  final List<TextEditingController> _appOtp =
      List.generate(_otpLen, (_) => TextEditingController());
  final List<FocusNode> _appFocus = List.generate(_otpLen, (_) => FocusNode());
  final List<TextEditingController> _coOtp =
      List.generate(_otpLen, (_) => TextEditingController());
  final List<FocusNode> _coFocus = List.generate(_otpLen, (_) => FocusNode());

  String get _appCode => _appOtp.map((c) => c.text).join();
  String get _coCode => _coOtp.map((c) => c.text).join();
  // Co-applicant passcode is only required when there's a co-applicant number.
  bool get _hasCo => widget.coApplicantMobile.trim().isNotEmpty;
  bool get _canVerify =>
      _appCode.length == _otpLen && (!_hasCo || _coCode.length == _otpLen);

  @override
  void initState() {
    super.initState();
    _startTimer('APPLICANT');
    if (_hasCo) _startTimer('CO_APPLICANT');
  }

  @override
  void dispose() {
    _appTimer?.cancel();
    _coTimer?.cancel();
    for (final c in [..._appOtp, ..._coOtp]) {
      c.dispose();
    }
    for (final f in [..._appFocus, ..._coFocus]) {
      f.dispose();
    }
    super.dispose();
  }

  bool _isCo(String t) => t == 'CO_APPLICANT';
  int _leftFor(String t) => _isCo(t) ? _coLeft : _appLeft;
  bool _resendingFor(String t) => _isCo(t) ? _coResending : _appResending;

  String _timerTextFor(String t) {
    final s = _leftFor(t);
    return '${(s ~/ 60).toString().padLeft(2, '0')}:'
        '${(s % 60).toString().padLeft(2, '0')}';
  }

  // Start (or restart) the countdown for just this person. The reset is a plain
  // assignment (no setState) so it's safe to call from initState; the per-second
  // tick rebuilds via setState.
  void _startTimer(String t) {
    if (_isCo(t)) {
      _coTimer?.cancel();
      _coLeft = _resendSeconds;
      _coTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          if (_coLeft <= 1) {
            _coLeft = 0;
            timer.cancel();
          } else {
            _coLeft--;
          }
        });
      });
    } else {
      _appTimer?.cancel();
      _appLeft = _resendSeconds;
      _appTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          if (_appLeft <= 1) {
            _appLeft = 0;
            timer.cancel();
          } else {
            _appLeft--;
          }
        });
      });
    }
  }

  void _onOtpChanged(List<FocusNode> focus, int i, String v) {
    if (v.isNotEmpty && i < _otpLen - 1) {
      focus[i + 1].requestFocus();
    } else if (v.isEmpty && i > 0) {
      focus[i - 1].requestFocus();
    }
    setState(() {});
  }

  // Clear ONLY this person's passcode boxes (after a resend) and focus the first
  // box so the new code can be typed straight away.
  void _clearOtpFor(String applicantType) {
    final ctrls = _isCo(applicantType) ? _coOtp : _appOtp;
    final focus = _isCo(applicantType) ? _coFocus : _appFocus;
    for (final c in ctrls) {
      c.clear();
    }
    if (focus.isNotEmpty) focus.first.requestFocus();
    setState(() {}); // reflect the cleared state (e.g. Verify button)
  }

  // Resend the OTP to a single applicant type (APPLICANT / CO_APPLICANT) via
  // /consent/resend-otp.
  Future<void> _onResend(String applicantType) async {
    // Only this person's own countdown / loader gates this resend.
    if (_leftFor(applicantType) > 0 || _resendingFor(applicantType)) return;
    setState(() {
      if (_isCo(applicantType)) {
        _coResending = true;
      } else {
        _appResending = true;
      }
    });
    try {
      final appId =
          int.tryParse(widget.applicationId.trim()) ?? widget.applicationId;
      // That person's number (shown on screen) — applicant vs co-applicant.
      final mobile = _isCo(applicantType)
          ? widget.coApplicantMobile
          : widget.applicantMobile;
      final res = await _repo.resendConsentOtp(
        applicationId: appId,
        consentIds: widget.consentIds,
        applicantType: applicantType,
        mobileNumber: mobile,
      );
      if (!mounted) return;
      final ok = res is Map && (res['success'] == true || res['status'] == true);
      final msg = (res is Map &&
              res['message'] is String &&
              (res['message'] as String).trim().isNotEmpty)
          ? (res['message'] as String).trim()
          : null;
      if (!ok) {
        _snack(msg ?? 'Could not resend passcode. Please try again.');
        return;
      }
      _snack(msg ?? 'Passcode resent', ok: true);
      _clearOtpFor(applicantType); // old passcode is now invalid → clear it
      _startTimer(applicantType); // restart ONLY this person's countdown
    } on ApiException catch (e) {
      if (mounted) _snack(e.message);
    } catch (_) {
      if (mounted) _snack('Something went wrong. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          if (_isCo(applicantType)) {
            _coResending = false;
          } else {
            _appResending = false;
          }
        });
      }
    }
  }

  // Verify the applicant + co-applicant OTPs in ONE call. On success → OTP
  // Verified Successfully screen; on failure → server message, stay here.
  Future<void> _onVerify() async {
    if (_verifying || !_canVerify) return;
    setState(() => _verifying = true);
    try {
      final appId =
          int.tryParse(widget.applicationId.trim()) ?? widget.applicationId;
      final res = await _repo.verifyConsentOtp(
        applicationId: appId,
        applicantOtp: _appCode,
        coApplicantOtp: _hasCo ? _coCode : '',
      );
      debugPrint('verify-otp response: $res');
      if (!mounted) return;
      final ok = res is Map && (res['success'] == true || res['status'] == true);
      final msg = (res is Map &&
              res['message'] is String &&
              (res['message'] as String).trim().isNotEmpty)
          ? (res['message'] as String).trim()
          : null;
      if (!ok) {
        _snack(msg ?? 'Passcode verification failed. Please try again.');
        return;
      }
      if (msg != null) _snack(msg, ok: true);
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ConsentCapturedScreen(lead: widget.lead),
      ));
    } on ApiException catch (e) {
      if (mounted) _snack(e.message);
    } catch (_) {
      if (mounted) _snack('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  void _snack(String msg, {bool ok = false}) {
    AppToast.show(context, msg,
        type: ok ? ToastType.success : ToastType.error);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppFlowScaffold(
      title: 'Consent Passcode Sent',
      stepText: 'Step 3 of 5',
      bottomBar: InteractionBottomBar(
        actionLabel: _verifying ? 'Verifying…' : 'Verify Passcode',
        enabled: _canVerify && !_verifying,
        onAction: _onVerify,
        onExit: () => Navigator.of(context)
            .pushNamedAndRemoveUntil(AppRoutes.home, (r) => false),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          const SizedBox(height: 8),
          Center(
            child: SuccessBadge(
              child: const Icon(Icons.lock_outline,
                  size: 38, color: AppColors.purple),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              // Server message when sent; otherwise the static confirmation.
              widget.message.trim().isNotEmpty
                  ? widget.message.trim()
                  : 'Consent Passcode has been sent to the applicant and '
                      'co-applicant.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, height: 1.4, color: p.title),
            ),
          ),
          const SizedBox(height: 18),
          // Sent To card — both numbers.
          FlowCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sent To',
                    style: TextStyle(fontSize: 13, color: p.subtitle)),
                const SizedBox(height: 8),
                _sentToLine(widget.applicantMobile, 'Applicant'),
                if (_hasCo) ...[
                  const SizedBox(height: 6),
                  _sentToLine(widget.coApplicantMobile, 'Co-Applicant'),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Applicant passcode.
          _passcodeCard(
            label: 'Enter Applicant Passcode',
            applicantType: 'APPLICANT',
            otp: _appOtp,
            focus: _appFocus,
          ),
          if (_hasCo) ...[
            const SizedBox(height: 14),
            // Co-Applicant passcode.
            _passcodeCard(
              label: 'Enter Co-Applicant Passcode',
              applicantType: 'CO_APPLICANT',
              otp: _coOtp,
              focus: _coFocus,
            ),
          ],
        ],
      ),
    );
  }

  Widget _sentToLine(String mobile, String who) {
    final p = context.palette;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: mobile.trim().isNotEmpty ? '+91 ${mobile.trim()}' : '—',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700, color: p.title),
          ),
          TextSpan(
            text: '  ($who)',
            style: TextStyle(fontSize: 13.5, color: p.subtitle),
          ),
        ],
      ),
    );
  }

  Widget _passcodeCard({
    required String label,
    required String applicantType, // APPLICANT / CO_APPLICANT (for resend)
    required List<TextEditingController> otp,
    required List<FocusNode> focus,
  }) {
    final p = context.palette;
    return FlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: p.title)),
              ),
              Text(_timerTextFor(applicantType),
                  style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.purple)),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () => _onResend(applicantType),
                behavior: HitTestBehavior.opaque,
                child: Text('Resend',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: _leftFor(applicantType) == 0
                            ? AppColors.deepOrange
                            : p.hint)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (var i = 0; i < _otpLen; i++) ...[
                _otpBox(otp, focus, i),
                if (i < _otpLen - 1) const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _otpBox(List<TextEditingController> otp, List<FocusNode> focus, int i) {
    final p = context.palette;
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: p.fieldBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: p.fieldBorder),
        ),
        child: TextField(  
          controller: otp[i],
          focusNode: focus[i],
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          maxLength: 1,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: TextStyle(
              fontSize: 20, fontWeight: FontWeight.w700, color: p.title),
          decoration: const InputDecoration(
            counterText: '',
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(vertical: 16),
            hintText: '–',
          ),
          onChanged: (v) => _onOtpChanged(focus, i, v),
        ),
      ),
    );
  }
}
