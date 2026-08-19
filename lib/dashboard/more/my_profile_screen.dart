import 'package:flutter/material.dart';
import '../../core/constants/app_assets.dart';
import '../../core/network/api_exception.dart';
import '../../data/repositories/profile_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_buttons.dart';
import '../widgets/interaction_ui.dart';
import 'edit_profile_screen.dart';
import 'more_scaffold.dart';
import '../../core/utils/date_format.dart';
import 'profile_data.dart';

/// My Profile — avatar + name/email header, a read-only details card, and an
/// "Edit Profile" action. Fetched from `POST /rm/get-profile`.
class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key});

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  final ProfileRepository _repo = ProfileRepository();
  ProfileData? _profile;
  bool _loading = true;
  String? _error;

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
      final p = await _repo.getProfile();
      if (!mounted) return;
      setState(() {
        _profile = p;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load profile. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MoreScaffold(
      title: 'My Profile',
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.purple))
          : _error != null
              ? _ErrorRetry(message: _error!, onRetry: _load)
              : _content(_profile!),
    );
  }

  Widget _content(ProfileData profile) {
    final p = context.palette;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        // Avatar header.
        InteractionCard(
          child: Row(
            children: [
              const _Avatar(size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.displayName,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: p.title,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      profile.email,
                      style: TextStyle(fontSize: 13.5, color: p.subtitle),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Details.
        InteractionCard(
          child: Column(
            children: [
              _DetailRow(label: 'Full Name', value: profile.fullName),
              _DetailRow(label: 'Mobile Number', value: profile.mobile),
              _DetailRow(label: 'Email Address', value: profile.email),
              _DetailRow(label: 'Date of Birth', value: formatDob(profile.dob)),
              _DetailRow(label: 'Gender', value: profile.gender),
              _DetailRow(
                label: 'Status',
                valueWidget: _StatusBadge(text: profile.status),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        PrimaryButton(
          label: 'Edit Profile',
          onPressed: () async {
            final updated = await Navigator.of(context).push<ProfileData>(
              MaterialPageRoute(
                builder: (_) => EditProfileScreen(profile: profile),
              ),
            );
            if (updated != null && mounted) setState(() => _profile = updated);
          },
        ),
      ],
    );
  }
}

/// Centered error message + Retry.
class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: p.subtitle)),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.asset(
        AppAssets.profileAvatar,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          width: size,
          height: size,
          color: AppColors.purple.withValues(alpha: 0.12),
          child: const Icon(Icons.person, color: AppColors.purple),
        ),
      ),
    );
  }
}

/// One "Label .......... Value" row in the details card.
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, this.value, this.valueWidget});
  final String label;
  final String? value;
  final Widget? valueWidget;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(fontSize: 14, color: p.subtitle),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: valueWidget ??
                Text(
                  value ?? '',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: p.title,
                  ),
                ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, size: 15, color: AppColors.success),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.success,
            ),
          ),
        ],
      ),
    );
  }
}
