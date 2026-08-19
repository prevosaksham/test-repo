import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/login/login_bloc.dart';
import '../core/utils/validators.dart';
import '../core/widgets/app_toast.dart';
import '../data/models/otp_args.dart';
import '../data/repositories/auth_repository.dart';
import '../routes/app_routes.dart';
import '../theme/app_colors.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/app_buttons.dart';
import '../widgets/labeled_text_field.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LoginBloc(repository: AuthRepository()),
      child: const _LoginView(),
    );
  }
}

class _LoginView extends StatefulWidget {
  const _LoginView();

  @override
  State<_LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<_LoginView> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    final email = _emailCtrl.text.trim();
    final pass = _passwordCtrl.text;
    if (email.isEmpty) {
      _toast('Please enter your email');
      return;
    }
    if (!Validators.isValidEmail(email)) {
      _toast('Please enter a valid email address');
      return;
    }
    if (pass.isEmpty) {
      _toast('Please enter your password');
      return;
    }
    context.read<LoginBloc>().add(
          LoginSubmitted(email: email, password: pass),
        );
  }

  void _toast(String m) => AppToast.show(context, m);

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<LoginBloc, LoginState>(
      listenWhen: (prev, curr) => prev.status != curr.status,
      listener: (context, state) {
        if (state.status == LoginStatus.failure) {
          _toast(state.errorMessage ?? 'Login failed');
        } else if (state.status == LoginStatus.otpRequired &&
            state.response != null) {
          final r = state.response!;
          Navigator.of(context).pushNamed(
            AppRoutes.otp,
            arguments: OtpArgs(
              sentTo: r.otpSentTo,
              email: _emailCtrl.text.trim(),
              flow: OtpFlow.login,
              loginToken: r.loginToken,
              expiresIn: r.expiresIn,
              resendCooldown: r.resendCooldown,
              maxResends: r.maxResends,
            ),
          );
        } else if (state.status == LoginStatus.success) {
          // No OTP needed — straight to home.
          Navigator.of(context)
              .pushNamedAndRemoveUntil(AppRoutes.home, (r) => false);
        }
      },
      builder: (context, state) {
        return AuthScaffold(
          // Login button pinned to the bottom of the page; scrolls with the
          // page when the content gets tall (small screen / keyboard).
          footer: PrimaryButton(
            label: 'Login',
            loading: state.isLoading,
            onPressed: state.isLoading ? null : _submit,
          ),
          children: [
            const AuthHeadingText(
              title: 'Login',
              subtitle: 'Please enter login credentials',
            ),
            const SizedBox(height: 14),
            FieldCard(
              children: [
                LabeledTextField(
                  label: 'Email ID',
                  hint: 'Enter Email',
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  suffixIcon: Icons.mail_outline,
                ),
                const SizedBox(height: 12),
                LabeledTextField(
                  label: 'Password',
                  hint: 'Enter Password',
                  controller: _passwordCtrl,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  suffixIcon: _obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  onSuffixTap: () => setState(() => _obscure = !_obscure),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () =>
                        Navigator.of(context).pushNamed(AppRoutes.forgot),
                    child: const Text(
                      'Forgot Password?',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
