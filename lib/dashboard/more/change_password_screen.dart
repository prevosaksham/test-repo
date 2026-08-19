import 'package:flutter/material.dart';
import '../../core/widgets/app_toast.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_buttons.dart';
import '../widgets/interaction_ui.dart';
import 'more_scaffold.dart';

/// Change Password — old / new / confirm fields with show-hide toggles.
/// Save is a static demo for now (no change-password API wired yet).
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _snack(String msg) => AppToast.show(context, msg);

  Future<void> _save() async {
    if (_old.text.isEmpty || _new.text.isEmpty || _confirm.text.isEmpty) {
      _snack('Please fill in all fields');
      return;
    }
    if (_new.text != _confirm.text) {
      _snack('New password and confirm password do not match');
      return;
    }
    setState(() => _saving = true);
    // No API yet — simulate success.
    if (!mounted) return;
    setState(() => _saving = false);
    _snack('Password updated');
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return MoreScaffold(
      title: 'Change Password',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        children: [
          InteractionCard(
            child: Column(
              children: [
                _PasswordField(label: 'Old Password', controller: _old),
                const SizedBox(height: 16),
                _PasswordField(label: 'New Password', controller: _new),
                const SizedBox(height: 16),
                _PasswordField(label: 'Confirm Password', controller: _confirm),
              ],
            ),
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            label: 'Save Password',
            loading: _saving,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}

class _PasswordField extends StatefulWidget {
  const _PasswordField({required this.label, required this.controller});
  final String label;
  final TextEditingController controller;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: TextStyle(fontSize: 13.5, color: p.label)),
        const SizedBox(height: 7),
        TextField(
          controller: widget.controller,
          obscureText: _obscure,
          style: TextStyle(fontSize: 14.5, color: p.title),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Enter Password',
            hintStyle: TextStyle(color: p.hint, fontSize: 14),
            filled: true,
            fillColor: p.fieldBg,
            suffixIcon: IconButton(
              splashRadius: 20,
              icon: Icon(
                _obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 20,
                color: p.iconGrey,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: p.fieldBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.purple),
            ),
          ),
        ),
      ],
    );
  }
}
