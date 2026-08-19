import 'package:flutter/material.dart';
import '../../core/constants/app_assets.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/widgets/app_icon.dart';
import '../../data/repositories/auth_repository.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_colors.dart';
// import '../more/change_password_screen.dart'; // hidden — Change Password off
import '../more/logout_dialog.dart';
import '../more/my_profile_screen.dart';
import '../more/privacy_policy_screen.dart';
import '../more/terms_conditions_screen.dart';
import '../widgets/dashboard_header.dart';

class MoreTab extends StatelessWidget {
  const MoreTab({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        const DashboardHeader(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            children: [
              _MoreItem(
                  icon: AppAssets.myProfile,
                  label: 'My Profile',
                  onTap: () => _open(context, const MyProfileScreen())),
              // Change Password — hidden for now.
              // _MoreItem(
              //     icon: AppAssets.changePassword,
              //     label: 'Change Password',
              //     onTap: () => _open(context, const ChangePasswordScreen())),
              _MoreItem(
                  icon: AppAssets.terms,
                  label: 'Terms & Conditions',
                  onTap: () => _open(context, const TermsConditionsScreen())),
              _MoreItem(
                  icon: AppAssets.privacy,
                  label: 'Privacy Policy',
                  onTap: () => _open(context, const PrivacyPolicyScreen())),
              _MoreItem(
                iconData: Icons.dark_mode, // Flutter built-in (clean vector)
                label: 'Dark Mode',
                trailing: Switch(
                  value: isDark,
                  activeThumbColor: AppColors.purple,
                  onChanged: (v) => ThemeController.instance.setDark(v),
                ),
                onTap: () => ThemeController.instance.setDark(!isDark),
              ),
              _MoreItem(
                icon: AppAssets.logout,
                label: 'Logout',
                onTap: () => _logout(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _logout(BuildContext context) async {
    final confirmed = await showLogoutDialog(context);
    if (!confirmed || !context.mounted) return;
    // Clear the session best-effort — even if it throws, still go to login.
    try {
      await AuthRepository().logout();
    } catch (_) {/* ignore — proceed to login regardless */}
    if (!context.mounted) return;
    // rootNavigator so it clears the whole stack (not a nested navigator).
    Navigator.of(context, rootNavigator: true)
        .pushNamedAndRemoveUntil(AppRoutes.login, (r) => false);
  }
}

class _MoreItem extends StatelessWidget {
  const _MoreItem({
    required this.label,
    required this.onTap,
    this.icon,
    this.iconData,
    this.trailing,
  });
  final String? icon; // SVG/PNG asset path (rendered via AppIcon)
  final IconData? iconData; // OR a built-in Material icon (takes priority)
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: p.cardBg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.fieldBorder),
            ),
            child: Row(
              children: [
                iconData != null
                    ? Icon(iconData, size: 24, color: AppColors.purple)
                    : AppIcon(icon!, size: 24, color: AppColors.purple),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 14,
                          height: 16 / 14, // Figma: 16px line box
                          fontWeight: FontWeight.w600,
                          color: p.title)),
                ),
                trailing ??
                    Icon(Icons.chevron_right, color: p.subtitle, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
