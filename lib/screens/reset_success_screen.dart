import 'package:flutter/material.dart';
import '../core/constants/app_assets.dart';
import '../routes/app_routes.dart';
import '../theme/app_colors.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/app_buttons.dart';

/// Final confirmation after a successful password reset.
class ResetSuccessScreen extends StatelessWidget {
  const ResetSuccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      footer: PrimaryButton(
        label: 'Back to Login',
        onPressed: () => Navigator.of(context)
            .pushNamedAndRemoveUntil(AppRoutes.login, (r) => false),
      ),
      children: [
        const SizedBox(height: 8),
        // Green success badge (single brand asset — see AppAssets.successCheck).
        Center(
          child: Image.asset(AppAssets.successCheck, width: 92, height: 92),
        ),
        const SizedBox(height: 20),
        const Text(
          'Successful !',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.success,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Your password has been reset\nsuccessfully.',
          textAlign: TextAlign.center,
          style:
              TextStyle(fontSize: 15, color: context.palette.subtitle, height: 1.4),
        ),
      ],
    );
  }
}
