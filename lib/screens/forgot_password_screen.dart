import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/forgot_password/forgot_password_bloc.dart';
import '../core/utils/validators.dart';
import '../core/widgets/app_toast.dart';
import '../data/models/otp_args.dart';
import '../data/repositories/auth_repository.dart';
import '../routes/app_routes.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/app_buttons.dart';
import '../widgets/labeled_text_field.dart';

class ForgotPasswordScreen extends StatelessWidget {
  const ForgotPasswordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ForgotPasswordBloc(repository: AuthRepository()),
      child: const _ForgotPasswordView(),
    );
  }
}

class _ForgotPasswordView extends StatefulWidget {
  const _ForgotPasswordView();

  @override
  State<_ForgotPasswordView> createState() => _ForgotPasswordViewState();
}

class _ForgotPasswordViewState extends State<_ForgotPasswordView> {
  final _emailCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      _toast('Please enter your email');
      return;
    }
    if (!Validators.isValidEmail(email)) {
      _toast('Please enter a valid email address');
      return;
    }
    context.read<ForgotPasswordBloc>().add(ForgotPasswordSubmitted(email: email));
  }

  void _toast(String m) => AppToast.show(context, m);

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ForgotPasswordBloc, ForgotPasswordState>(
      listenWhen: (p, c) => p.status != c.status,
      listener: (context, state) {
        if (state.status == ForgotStatus.failure) {
          _toast(state.errorMessage ?? 'Could not send OTP');
        } else if (state.status == ForgotStatus.success &&
            state.response != null) {
          final r = state.response!;
          Navigator.of(context).pushNamed(
            AppRoutes.otp,
            arguments: OtpArgs(
              sentTo: r.otpSentTo,
              email: _emailCtrl.text.trim(),
              flow: OtpFlow.forgotPassword,
              expiresIn: r.expiresIn,
              resendCooldown: r.resendCooldown,
              maxResends: r.maxResends,
            ),
          );
        }
      },
      builder: (context, state) {
        return AuthScaffold(
          showBack: true,
          // Buttons pinned to the bottom of the page (like Login); scroll with
          // the page when content gets tall.
          footer: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PrimaryButton(
                label: 'Continue',
                loading: state.isLoading,
                onPressed: state.isLoading ? null : _submit,
              ),
              const SizedBox(height: 12),
              SecondaryButton(
                label: 'Back to Login',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          children: [
            const AuthHeadingText(
              title: 'Forgot Password',
              subtitle: 'Please enter your Email',
            ),
            const SizedBox(height: 14),
            FieldCard(
              children: [
                LabeledTextField(
                  label: 'Email ID',
                  hint: 'Enter Email',
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  suffixIcon: Icons.mail_outline,
                  onSubmitted: (_) => _submit(),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
