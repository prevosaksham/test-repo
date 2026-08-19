import 'package:flutter/material.dart';
import '../../core/constants/app_assets.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/local/auth_storage.dart';
import '../../data/repositories/profile_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_buttons.dart';
import '../widgets/interaction_ui.dart';
import 'more_scaffold.dart';
import 'profile_data.dart';

/// Edit Profile — editable name/mobile/email/DOB over an avatar header with an
/// edit badge. Save is a static demo for now (pops with a confirmation).
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.profile});
  final ProfileData profile;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _name =
      TextEditingController(text: widget.profile.fullName);
  late final TextEditingController _mobile =
      TextEditingController(text: widget.profile.mobile);
  late final TextEditingController _email =
      TextEditingController(text: widget.profile.email);
  late final TextEditingController _dob =
      TextEditingController(text: widget.profile.dob);

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadEditProfile();
  }

  // Refresh the form from GET /rm/edit-profile. The fields are already prefilled
  // from the passed profile, so on any failure we just keep those.
  Future<void> _loadEditProfile() async {
    try {
      final p = await ProfileRepository().getEditProfile();
      if (!mounted) return;
      setState(() {
        if (p.fullName.isNotEmpty) _name.text = p.fullName;
        if (p.mobile.isNotEmpty) _mobile.text = p.mobile;
        if (p.email.isNotEmpty) _email.text = p.email;
        if (p.dob.isNotEmpty) _dob.text = p.dob;
      });
    } catch (_) {
      /* keep the passed-profile values */
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _mobile.dispose();
    _email.dispose();
    _dob.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    // DOB can never be in the future — cap at today. Only past dates (this year
    // and earlier) are selectable.
    final today = DateTime.now();
    final parsed = _parseDob(_dob.text);
    // Open at the stored DOB only when it's a valid past date, else at 2000.
    final initial = (parsed != null && !parsed.isAfter(today))
        ? parsed
        : DateTime(2000);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1950),
      lastDate: today, // no future dates
    );
    if (picked != null) {
      _dob.text =
          '${_two(picked.day)}/${_two(picked.month)}/${picked.year}';
    }
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static DateTime? _parseDob(String v) {
    final parts = v.split('/');
    if (parts.length != 3) return null;
    final d = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final y = int.tryParse(parts[2]);
    if (d == null || m == null || y == null) return null;
    return DateTime(y, m, d);
  }

  void _snack(String msg, {bool ok = false}) {
    if (!mounted) return;
    AppToast.show(context, msg,
        type: ok ? ToastType.success : ToastType.error);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final res = await ProfileRepository().updateProfile(
        fullName: _name.text.trim(),
        mobile: _mobile.text.trim(),
        dateOfBirth: _dob.text.trim(),
      );
      if (!mounted) return;
      final ok = res is Map && (res['success'] == true || res['status'] == true);
      final msg = (res is Map &&
              res['message'] is String &&
              (res['message'] as String).trim().isNotEmpty)
          ? (res['message'] as String).trim()
          : (ok ? 'Profile updated' : 'Could not update profile');
      _snack(msg, ok: ok);
      if (!ok) return;
      // Saved → also patch the locally-stored login session so the new name /
      // mobile reflect everywhere that reads it (dashboard header, etc.).
      await AuthStorage.instance.updateProfile(
        fullName: _name.text.trim(),
        mobile: _mobile.text.trim(),
      );
      // Return the updated values so the previous screen refreshes.
      final updated = widget.profile.copyWith(
        fullName: _name.text.trim(),
        mobile: _mobile.text.trim(),
        email: _email.text.trim(),
        dob: _dob.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(updated);
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return MoreScaffold(
      title: 'Edit Profile',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        children: [
          // Avatar header with edit badge.
          InteractionCard(
            child: Row(
              children: [
                _EditableAvatar(onTap: () {/* image picker hook (later) */}),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.profile.displayName,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: p.title,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.profile.email,
                        style: TextStyle(fontSize: 13.5, color: p.subtitle),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          InteractionCard(
            child: Column(
              children: [
                _LabeledField(
                  label: 'Full Name',
                  controller: _name,
                  hint: 'Enter full name',
                ),
                const SizedBox(height: 14),
                _LabeledField(
                  label: 'Mobile Number',
                  controller: _mobile,
                  hint: 'Enter mobile number',
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 14),
                _LabeledField(
                  label: 'Email Address',
                  controller: _email,
                  hint: 'Enter email address',
                  keyboardType: TextInputType.emailAddress,
                  enabled: false, // email can't be edited
                ),
                const SizedBox(height: 14),
                _LabeledField(
                  label: 'Date of Birth',
                  controller: _dob,
                  hint: 'dd/mm/yyyy',
                  readOnly: true,
                  onTap: _pickDate,
                  suffix: Icon(Icons.calendar_today_outlined,
                      size: 18, color: p.subtitle),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          PrimaryButton(label: 'Save', loading: _saving, onPressed: _save),
        ],
      ),
    );
  }
}

class _EditableAvatar extends StatelessWidget {
  const _EditableAvatar({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              AppAssets.profileAvatar,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: 56,
                height: 56,
                color: AppColors.purple.withValues(alpha: 0.12),
                child: const Icon(Icons.person, color: AppColors.purple),
              ),
            ),
          ),
          Positioned(
            top: -4,
            right: -4,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                gradient: AppColors.buttonGradient,
                shape: BoxShape.circle,
                border: Border.all(color: p.cardBg, width: 2),
              ),
              child: const Icon(Icons.edit, size: 12, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

/// Label above a bordered text field (matches the Edit-Profile mockup).
class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.controller,
    this.hint,
    this.keyboardType,
    this.readOnly = false,
    this.enabled = true,
    this.onTap,
    this.suffix,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final bool readOnly;
  final bool enabled; // false → disabled (greyed, not editable)
  final VoidCallback? onTap;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 13.5, color: p.label)),
        const SizedBox(height: 7),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          readOnly: readOnly,
          enabled: enabled,
          onTap: onTap,
          style: TextStyle(
              fontSize: 14.5, color: enabled ? p.title : p.subtitle),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: TextStyle(color: p.hint, fontSize: 14),
            filled: true,
            fillColor: enabled ? p.fieldBg : p.otpBoxBg,
            suffixIcon: suffix,
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
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: p.fieldBorder),
            ),
          ),
        ),
      ],
    );
  }
}
