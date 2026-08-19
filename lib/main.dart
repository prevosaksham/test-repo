import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'bloc/connectivity/connectivity_cubit.dart';
import 'core/device/app_device.dart';
import 'core/theme/theme_controller.dart';
import 'routes/app_routes.dart';
import 'theme/app_colors.dart';
import 'widgets/connectivity_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppDevice.init(); // read Android OS version for the edge-to-edge gap
  await ThemeController.instance.load(); // restore saved light/dark choice
  // Lock the app to portrait orientation.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const ErikshaApp());
}

class ErikshaApp extends StatelessWidget {
  const ErikshaApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Provide the connectivity monitor ABOVE MaterialApp so it survives theme
    // rebuilds, and mount the global offline/online banner on every page via
    // MaterialApp.builder.
    return BlocProvider(
      create: (_) => ConnectivityCubit(),
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: ThemeController.instance.mode,
        builder: (context, mode, _) {
          return MaterialApp(
            title: 'Pink EV_LOS',
            debugShowCheckedModeBanner: false,
            theme: _buildTheme(Brightness.light, AppPalette.light),
            darkTheme: _buildTheme(Brightness.dark, AppPalette.dark),
            themeMode: mode, // system, or the user's Dark Mode choice
            initialRoute: AppRoutes.splash,
            onGenerateRoute: AppRoutes.onGenerateRoute,
            navigatorObservers: [appRouteObserver, RouteNameObserver()],
            builder: (context, child) {
              // App-wide responsiveness: clamp the system text scale so very
              // large/small font settings can't break layouts on any device.
              final mq = MediaQuery.of(context);
              return MediaQuery(
                data: mq.copyWith(
                  textScaler: mq.textScaler
                      .clamp(minScaleFactor: 0.9, maxScaleFactor: 1.2),
                ),
                child: ConnectivityGate(
                  child: _TabletCenter(child: child ?? const SizedBox.shrink()),
                ),
              );
            },
          );
        },
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness, AppPalette palette) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: palette.surface,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.deepOrange,
        primary: AppColors.primary,
        brightness: brightness,
      ),
      fontFamily: 'Roboto',
      extensions: [palette],
    );
  }
}

/// Centres the whole app at a phone-like max width on wide screens (tablets) so
/// pages don't stretch edge-to-edge. Phones are narrower than [_maxWidth], so
/// they pass through unchanged. The extra space on either side is filled with
/// the theme background so it blends in.
///
/// Purely presentational — it only constrains width and reports that width via
/// MediaQuery (so size-based layouts stay consistent). No screen logic, state,
/// or callback is touched.
class _TabletCenter extends StatelessWidget {
  const _TabletCenter({required this.child});
  final Widget child;

  // A comfortable phone-like content width; tablets centre content at this cap.
  static const double _maxWidth = 600;

  // Routes kept full-bleed (edge-to-edge) even on tablets — the auth flow
  // (splash + AuthScaffold pages) has full-screen branding/backgrounds that
  // shouldn't be boxed in, and AuthScaffold already scales itself responsively.
  static const Set<String?> _fullBleed = {
    AppRoutes.splash,
    AppRoutes.login,
    AppRoutes.forgot,
    AppRoutes.otp,
    AppRoutes.reset,
    AppRoutes.success,
  };

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: currentRouteName,
      builder: (context, route, _) {
        final mq = MediaQuery.of(context);
        if (_fullBleed.contains(route) || mq.size.width <= _maxWidth) {
          return child;
        }
        return ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxWidth),
              // Report the constrained width to descendants so any size-based
              // layout matches the actual render width (avoids overflow).
              child: MediaQuery(
                data: mq.copyWith(size: Size(_maxWidth, mq.size.height)),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}
