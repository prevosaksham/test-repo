import 'dart:async';
import 'package:flutter/material.dart';
import '../core/network/token_store.dart';
import '../data/local/auth_storage.dart';
import '../routes/app_routes.dart';
import '../theme/app_colors.dart';
import '../widgets/sfl_logo.dart';

/// Branded splash. Loads any saved session and routes to Home (logged in) or
/// Login, after a short delay.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final results = await Future.wait([
      AuthStorage.instance.load(),
      Future.delayed(const Duration(seconds: 2)),
    ]);
    if (!mounted) return;
    final session = results.first;
    if (session != null && session.accessToken.isNotEmpty) {
      TokenStore.instance.authToken = session.accessToken;
      Navigator.of(context).pushReplacementNamed(AppRoutes.home);
    } else {
      Navigator.of(context).pushReplacementNamed(AppRoutes.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: Center(child: SflLogo(size: (w * 0.78).clamp(220.0, 340.0))),
      ),
    );
  }
}
