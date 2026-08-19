import 'package:flutter/material.dart';

/// Brand colours + gradients for the SFL RM app. These stay the SAME in light
/// and dark mode (brand identity). Mode-specific surfaces/text live in
/// [AppPalette] below and are read via `context.palette`.
class AppColors {
  AppColors._();

  // Brand oranges (top -> bottom of the background gradient).
  static const Color amber = Color(0xFFFBA918);
  static const Color orange = Color(0xFFF6831D);
  static const Color deepOrange = Color(0xFFEA4313);

  // Accent used for links / outlined buttons / "Forgot Password?".
  static const Color primary = Color(0xFFEF5A24);

  // Purple accent — Lead IDs, stat-card icons, active tab/nav, brand mark.
  static const Color purple = Color(0xFF5B3FA0);
  static const Color purpleDeep = Color(0xFF3A2A7A);

  // Chart / status palette (Reports + lead badges).
  static const Color chartNew = Color(0xFF6C4FB0);
  static const Color chartApproved = Color(0xFF2EA66B);
  static const Color chartProgress = Color(0xFFF1A93B);
  static const Color statusRed = Color(0xFFE2574C);
  static const Color statusBlue = Color(0xFF54A0E8);

  // Pure white — only for content drawn ON the orange gradient (logo circle,
  // back button), which is the same in both modes.
  static const Color white = Color(0xFFFFFFFF);

  // Status.
  static const Color success = Color(0xFF1E8E3E);

  /// Splash background — full-height amber → deep red (matches Splash mockup,
  /// sampled: top #FAA006 … bottom #DC1D21).
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFFFAA006),
      Color(0xFFF38209),
      Color(0xFFED722A),
      Color(0xFFE23719),
      Color(0xFFDC1D21),
    ],
    stops: [0.0, 0.25, 0.50, 0.78, 1.0],
  );

  /// Auth screens — gradient compressed so the deep red lands just above the
  /// white sheet's curve (matches Login/Forgot mockups, sampled: top #FA9C05 …
  /// at the curve #E33E18).
  static const LinearGradient authGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFFFA9C05),
      Color(0xFFF07D12),
      Color(0xFFE85513),
      Color(0xFFE33E18),
      Color(0xFFDD2419),
    ],
    stops: [0.0, 0.20, 0.34, 0.45, 1.0],
  );

  /// Dashboard top header (orange → red), used on Home/My Leads/Reports/More.
  static const LinearGradient headerGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFF7951E), Color(0xFFE5331A)],
  );

  /// Gradient used for the primary (filled) buttons.
  static const LinearGradient buttonGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFFF7941E), Color(0xFFE83C12)],
  );
}

/// Mode-aware surface + text palette. Registered on [ThemeData.extensions] for
/// both light and dark themes, so it follows the system theme automatically.
/// Access via `context.palette` (see the extension at the bottom).
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.surface,
    required this.cardBg,
    required this.fieldBg,
    required this.fieldBorder,
    required this.otpBoxBg,
    required this.title,
    required this.label,
    required this.subtitle,
    required this.hint,
    required this.iconGrey,
  });

  /// The white "sheet" / page background.
  final Color surface;

  /// Grey card that wraps form fields.
  final Color cardBg;
  final Color fieldBg;
  final Color fieldBorder;
  final Color otpBoxBg;

  // Text / icon greys.
  final Color title;
  final Color label;
  final Color subtitle;
  final Color hint;
  final Color iconGrey;

  static const AppPalette light = AppPalette(
    surface: Color(0xFFFFFFFF),
    cardBg: Color(0xFFF7F7F9),
    fieldBg: Color(0xFFFFFFFF),
    fieldBorder: Color(0xFFE3E3E6),
    otpBoxBg: Color(0xFFF1F1F3),
    title: Color(0xFF222222),
    label: Color(0xFF333333),
    subtitle: Color(0xFF7B7B7B),
    hint: Color(0xFF9E9E9E),
    iconGrey: Color(0xFF9A9A9A),
  );

  static const AppPalette dark = AppPalette(
    surface: Color(0xFF17171A),
    cardBg: Color(0xFF202024),
    fieldBg: Color(0xFF26262B),
    fieldBorder: Color(0xFF3A3A41),
    otpBoxBg: Color(0xFF26262B),
    title: Color(0xFFF2F2F4),
    label: Color(0xFFDADADE),
    subtitle: Color(0xFFA6A6AD),
    hint: Color(0xFF85858C),
    iconGrey: Color(0xFF9A9A9F),
  );

  @override
  AppPalette copyWith({
    Color? surface,
    Color? cardBg,
    Color? fieldBg,
    Color? fieldBorder,
    Color? otpBoxBg,
    Color? title,
    Color? label,
    Color? subtitle,
    Color? hint,
    Color? iconGrey,
  }) {
    return AppPalette(
      surface: surface ?? this.surface,
      cardBg: cardBg ?? this.cardBg,
      fieldBg: fieldBg ?? this.fieldBg,
      fieldBorder: fieldBorder ?? this.fieldBorder,
      otpBoxBg: otpBoxBg ?? this.otpBoxBg,
      title: title ?? this.title,
      label: label ?? this.label,
      subtitle: subtitle ?? this.subtitle,
      hint: hint ?? this.hint,
      iconGrey: iconGrey ?? this.iconGrey,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      surface: Color.lerp(surface, other.surface, t)!,
      cardBg: Color.lerp(cardBg, other.cardBg, t)!,
      fieldBg: Color.lerp(fieldBg, other.fieldBg, t)!,
      fieldBorder: Color.lerp(fieldBorder, other.fieldBorder, t)!,
      otpBoxBg: Color.lerp(otpBoxBg, other.otpBoxBg, t)!,
      title: Color.lerp(title, other.title, t)!,
      label: Color.lerp(label, other.label, t)!,
      subtitle: Color.lerp(subtitle, other.subtitle, t)!,
      hint: Color.lerp(hint, other.hint, t)!,
      iconGrey: Color.lerp(iconGrey, other.iconGrey, t)!,
    );
  }
}

/// Short accessor: `context.palette.title`, etc.
extension AppPaletteX on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
}
