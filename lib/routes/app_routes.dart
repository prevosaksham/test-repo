import 'package:flutter/material.dart';
import '../data/models/otp_args.dart';
import '../screens/splash_screen.dart';
import '../screens/login_screen.dart';
import '../screens/forgot_password_screen.dart';
import '../screens/otp_verification_screen.dart';
import '../screens/reset_password_screen.dart';
import '../screens/reset_success_screen.dart';
import '../dashboard/dashboard_shell.dart';

/// App-wide route observer. The DashboardShell subscribes to it so it can
/// refresh all its tabs whenever a PAGE pushed on top of it is popped (i.e. the
/// user exits any sub-page back to the dashboard).
///
/// Typed to [PageRoute] (not ModalRoute) on purpose: dialogs/popups (filter,
/// consent mode, logout) are PopupRoutes, so closing them must NOT trigger a
/// dashboard refresh (which would reset the My Leads status filter + reload).
final RouteObserver<PageRoute<dynamic>> appRouteObserver =
    RouteObserver<PageRoute<dynamic>>();

/// The name of the top-most route — kept in sync by [RouteNameObserver]. The
/// responsive wrapper reads this to keep full-bleed screens (splash, login)
/// edge-to-edge on tablets while centring every other page.
final ValueNotifier<String?> currentRouteName =
    ValueNotifier<String?>(AppRoutes.splash);

/// Tracks the top route's name into [currentRouteName]. Purely observational —
/// it never changes navigation behaviour.
class RouteNameObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      currentRouteName.value = route.settings.name;
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      currentRouteName.value = newRoute?.settings.name;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      currentRouteName.value = previousRoute?.settings.name;
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      currentRouteName.value = previousRoute?.settings.name;
}

/// Named routes for the auth flow.
class AppRoutes {
  AppRoutes._();

  static const String splash = '/';
  static const String login = '/login';
  static const String forgot = '/forgot';
  static const String otp = '/otp';
  static const String reset = '/reset';
  static const String success = '/success';
  static const String home = '/home';

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case splash:
        return _page(const SplashScreen(), settings);
      case login:
        return _page(const LoginScreen(), settings);
      case forgot:
        return _page(const ForgotPasswordScreen(), settings);
      case otp:
        final args = settings.arguments as OtpArgs?;
        return _page(
          OtpVerificationScreen(
            args: args ??
                const OtpArgs(sentTo: '', flow: OtpFlow.forgotPassword),
          ),
          settings,
        );
      case reset:
        // Expects the real email (String) for the reset-password call.
        final email = (settings.arguments as String?) ?? '';
        return _page(ResetPasswordScreen(email: email), settings);
      case success:
        return _page(const ResetSuccessScreen(), settings);
      case home:
        return _page(const DashboardShell(), settings);
      default:
        return _page(const LoginScreen(), settings);
    }
  }

  static MaterialPageRoute _page(Widget child, RouteSettings settings) =>
      MaterialPageRoute(builder: (_) => child, settings: settings);
}
