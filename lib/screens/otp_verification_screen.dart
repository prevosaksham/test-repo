import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/otp/otp_bloc.dart';
import '../data/models/otp_args.dart';
import '../core/widgets/app_toast.dart';
import '../data/repositories/auth_repository.dart';
import '../routes/app_routes.dart';
import '../theme/app_colors.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/app_buttons.dart';
import '../widgets/otp_input.dart';

class OtpVerificationScreen extends StatelessWidget {
  const OtpVerificationScreen({super.key, required this.args});

  final OtpArgs args;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => OtpBloc(repository: AuthRepository()),
      child: _OtpView(args: args),
    );
  }
}

class _OtpView extends StatefulWidget {
  const _OtpView({required this.args});
  final OtpArgs args;

  @override
  State<_OtpView> createState() => _OtpViewState();
}

class _OtpViewState extends State<_OtpView> {
  Timer? _timer;
  int _remaining = 0;
  int _resendsUsed = 0;
  String _otp = '';
  // Bumped on resend → re-keys the OtpInput so it rebuilds empty (clears the
  // old code the user had typed, since a fresh OTP is on its way).
  int _otpResetSeq = 0;

  OtpArgs get args => widget.args;

  @override
  void initState() {
    super.initState();
    _startCooldown(args.resendCooldown);
  }

  void _startCooldown(int seconds) {
    _timer?.cancel();
    setState(() => _remaining = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_remaining <= 1) {
        t.cancel();
        setState(() => _remaining = 0);
      } else {
        setState(() => _remaining--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _timerText {
    final m = (_remaining ~/ 60).toString().padLeft(2, '0');
    final s = (_remaining % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _toast(String m) => AppToast.show(context, m);

  void _onVerify() {
    FocusScope.of(context).unfocus();
    if (_otp.length < 6) {
      _toast('Please enter the 6-digit OTP');
      return;
    }
    if (args.flow == OtpFlow.login) {
      context
          .read<OtpBloc>()
          .add(OtpVerifyRequested(loginToken: args.loginToken, otp: _otp));
    } else {
      // Forgot flow: verify the OTP with the backend first (required before
      // reset-password). On success the listener routes to the reset screen.
      context
          .read<OtpBloc>()
          .add(OtpForgotVerifyRequested(email: args.email, otp: _otp));
    }
  }

  void _onResend() {
    if (_remaining > 0) return;
    if (_resendsUsed >= args.maxResends) {
      _toast('Maximum resend attempts reached');
      return;
    }
    // Clear the previously typed OTP — a new code is being sent.
    setState(() {
      _otp = '';
      _otpResetSeq++;
    });
    if (args.flow == OtpFlow.forgotPassword) {
      context.read<OtpBloc>().add(OtpResendRequested(email: args.email));
    } else {
      // Login-flow resend API not available yet — restart cooldown locally.
      _resendsUsed++;
      _startCooldown(args.resendCooldown);
      _toast('OTP resent');
    }
  }

  @override
  Widget build(BuildContext context) {
    final sentTo = args.sentTo;
    final subtitle = sentTo.isEmpty
        ? 'Please enter the verification code sent to your \n email.'
        : 'Please enter the verification code sent to your \n email $sentTo';

    return BlocConsumer<OtpBloc, OtpState>(
      listenWhen: (p, c) => p.status != c.status,
      listener: (context, state) {
        switch (state.status) {
          case OtpStatus.verified:
            Navigator.of(context)
                .pushNamedAndRemoveUntil(AppRoutes.home, (r) => false);
            break;
          case OtpStatus.forgotVerified:
            // OTP confirmed — now allowed to set a new password.
            Navigator.of(context)
                .pushNamed(AppRoutes.reset, arguments: args.email);
            break;
          case OtpStatus.verifyFailure:
            _toast(state.errorMessage ?? 'OTP verification failed');
            break;
          case OtpStatus.resent:
            _resendsUsed = state.resend?.resendCount ?? (_resendsUsed + 1);
            _startCooldown(state.resend?.resendCooldown ?? args.resendCooldown);
            _toast('OTP resent');
            break;
          case OtpStatus.resendFailure:
            _toast(state.errorMessage ?? 'Could not resend OTP');
            break;
          default:
            break;
        }
      },
      builder: (context, state) {
        final canResend = _remaining == 0 &&
            _resendsUsed < args.maxResends &&
            !state.isResending;
        return AuthScaffold(
          showBack: true,
          // Buttons pinned to the bottom of the page (like Login); scroll with
          // the page when content gets tall.
          footer: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SecondaryButton(
                label:
                    _remaining > 0 ? 'Resend OTP ($_timerText)' : 'Resend OTP',
                onPressed: canResend ? _onResend : null,
              ),
              const SizedBox(height: 12),
              PrimaryButton(
                label: 'Verify',
                loading: state.isVerifying,
                onPressed: state.isVerifying ? null : _onVerify,
              ),
            ],
          ),
          children: [
            AuthHeadingText(title: 'OTP Verification', subtitle: subtitle),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
              decoration: BoxDecoration(
                color: context.palette.cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.palette.fieldBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Enter OTP',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: context.palette.label,
                        ),
                      ),
                      Text(
                        _remaining > 0 ? _timerText : '00:00',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF3A2EAE),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  OtpInput(
                    key: ValueKey(_otpResetSeq),
                    onChanged: (v) => _otp = v,
                    onCompleted: (v) => _otp = v,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
