import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/reset_password/reset_password_bloc.dart';
import '../core/widgets/app_toast.dart';
import '../data/repositories/auth_repository.dart';
import '../routes/app_routes.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/app_buttons.dart';
import '../widgets/labeled_text_field.dart';

class ResetPasswordScreen extends StatelessWidget {
  const ResetPasswordScreen({super.key, required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ResetPasswordBloc(repository: AuthRepository()),
      child: _ResetPasswordView(email: email),
    );
  }
}

class _ResetPasswordView extends StatefulWidget {
  const _ResetPasswordView({required this.email});
  final String email;

  @override
  State<_ResetPasswordView> createState() => _ResetPasswordViewState();
}

class _ResetPasswordViewState extends State<_ResetPasswordView> {
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure1 = true;
  bool _obscure2 = true;

  @override
  void dispose() {
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    final p1 = _passCtrl.text;
    final p2 = _confirmCtrl.text;
    if (p1.isEmpty || p2.isEmpty) {
      _toast('Please fill both fields');
      return;
    }
    if (p1.length < 6) {
      _toast('Password must be at least 6 characters');
      return;
    }
    if (p1 != p2) {
      _toast('Passwords do not match');
      return;
    }
    context
        .read<ResetPasswordBloc>()
        .add(ResetPasswordSubmitted(email: widget.email, newPassword: p1));
  }

  void _toast(String m) => AppToast.show(context, m);

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ResetPasswordBloc, ResetPasswordState>(
      listenWhen: (p, c) => p.status != c.status,
      listener: (context, state) {
        if (state.status == ResetStatus.failure) {
          _toast(state.errorMessage ?? 'Could not reset password');
        } else if (state.status == ResetStatus.success) {
          Navigator.of(context)
              .pushNamedAndRemoveUntil(AppRoutes.success, (r) => false);
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
                label: 'Reset Password',
                loading: state.isLoading,
                onPressed: state.isLoading ? null : _submit,
              ),
              const SizedBox(height: 12),
              SecondaryButton(
                label: 'Back to Login',
                onPressed: () => Navigator.of(context)
                    .pushNamedAndRemoveUntil(AppRoutes.login, (r) => false),
              ),
            ],
          ),
          children: [
            const AuthHeadingText(
              title: 'Reset Password',
              subtitle: 'Please enter New Password',
            ),
            const SizedBox(height: 14),
            FieldCard(
              children: [
                LabeledTextField(
                  label: 'New Password',
                  hint: 'Enter New Password',
                  controller: _passCtrl,
                  obscureText: _obscure1,
                  textInputAction: TextInputAction.next,
                  suffixIcon: _obscure1
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  onSuffixTap: () => setState(() => _obscure1 = !_obscure1),
                ),
                const SizedBox(height: 16),
                LabeledTextField(
                  label: 'Confirm New Password',
                  hint: 'Confirm New Password',
                  controller: _confirmCtrl,
                  obscureText: _obscure2,
                  textInputAction: TextInputAction.done,
                  suffixIcon: _obscure2
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  onSuffixTap: () => setState(() => _obscure2 = !_obscure2),
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
