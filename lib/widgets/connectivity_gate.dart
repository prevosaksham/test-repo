import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/connectivity/connectivity_cubit.dart';
import '../theme/app_colors.dart';

/// Wraps every page (mounted via `MaterialApp.builder`) with a global
/// connectivity banner driven by [ConnectivityCubit]:
///   • offline → a red "Your internet connection is gone" bar
///   • just back online → a green "Back online" flash for a few seconds
/// The banner floats at the bottom so it doesn't shift page layout.
class ConnectivityGate extends StatelessWidget {
  const ConnectivityGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConnectivityCubit, ConnectivityState>(
      builder: (context, state) {
        final offline = state.isOffline;
        final online = state.justRestored;
        return Stack(
          children: [
            child,
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: (offline || online)
                    ? _Banner(online: online, key: ValueKey(online))
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.online, super.key});
  final bool online;

  @override
  Widget build(BuildContext context) {
    final color = online ? AppColors.success : AppColors.statusRed;
    final icon = online ? Icons.wifi : Icons.wifi_off_rounded;
    final text =
        online ? 'Back online' : 'Your internet connection is gone';
    return Material(
      color: color,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
