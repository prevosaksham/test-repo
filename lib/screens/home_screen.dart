import 'package:flutter/material.dart';
import '../data/local/auth_storage.dart';
import '../data/repositories/auth_repository.dart';
import '../routes/app_routes.dart';
import '../theme/app_colors.dart';

/// Minimal landing screen after a successful login, proving the session was
/// saved. Replace with the real RM dashboard later.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = AuthStorage.instance.current?.user;
    final p = context.palette;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.deepOrange,
        foregroundColor: Colors.white,
        title: const Text('Home'),
        actions: [
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await AuthRepository().logout();
              if (context.mounted) {
                Navigator.of(context)
                    .pushNamedAndRemoveUntil(AppRoutes.login, (r) => false);
              }
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome, ${user?.fullName.isNotEmpty == true ? user!.fullName : 'User'} 👋',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              user?.role ?? '',
              style: TextStyle(color: p.subtitle, fontSize: 14),
            ),
            const SizedBox(height: 20),
            if (user != null) ...[
              _row(p, 'User Code', user.userCode),
              _row(p, 'Email', user.email),
              _row(p, 'Mobile', user.mobile),
              _row(p, 'City', user.city),
              _row(p, 'State', user.state),
              _row(p, 'Pin Code', user.pinCode),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(AppPalette p, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(k,
                  style: TextStyle(
                      color: p.subtitle, fontWeight: FontWeight.w600)),
            ),
            Expanded(
              child: Text(v.isEmpty ? '-' : v,
                  style: TextStyle(color: p.title)),
            ),
          ],
        ),
      );
}
