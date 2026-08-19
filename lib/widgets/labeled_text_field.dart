import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Light-grey rounded card that groups one or more [LabeledTextField]s,
/// matching the mockups where fields sit inside a soft container.
class FieldCard extends StatelessWidget {
  const FieldCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: p.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.fieldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

/// A label sitting above a bordered white input field with an optional
/// trailing icon (mail, eye, etc.).
class LabeledTextField extends StatelessWidget {
  const LabeledTextField({
    super.key,
    required this.label,
    required this.hint,
    this.controller,
    this.obscureText = false,
    this.keyboardType,
    this.suffixIcon,
    this.onSuffixTap,
    this.textInputAction,
    this.onSubmitted,
  });

  final String label;
  final String hint;
  final TextEditingController? controller;
  final bool obscureText;
  final TextInputType? keyboardType;
  final IconData? suffixIcon;
  final VoidCallback? onSuffixTap;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: p.label,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          // Email/password must never be auto-capitalized or auto-corrected on
          // mobile — otherwise "kapil" becomes "Kapil" and login fails (401).
          textCapitalization: TextCapitalization.none,
          autocorrect: false,
          enableSuggestions: false,
          style: TextStyle(fontSize: 15, color: p.title),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: p.hint, fontSize: 14),
            filled: true,
            fillColor: p.fieldBg,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            suffixIcon: suffixIcon == null
                ? null
                : IconButton(
                    onPressed: onSuffixTap,
                    icon: Icon(suffixIcon, color: p.iconGrey, size: 20),
                  ),
            enabledBorder: _border(p.fieldBorder),
            focusedBorder: _border(AppColors.primary),
            border: _border(p.fieldBorder),
          ),
        ),
      ],
    );
  }

  OutlineInputBorder _border(Color c) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c, width: 1.2),
      );
}
