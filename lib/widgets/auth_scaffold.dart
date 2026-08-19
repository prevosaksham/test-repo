import 'package:flutter/material.dart';
import '../core/device/app_device.dart';
import '../theme/app_colors.dart';
import 'sfl_logo.dart';

/// Shared layout for every auth screen:
///   • full-screen orange gradient
///   • optional back button
///   • SFL logo in the upper area (shrinks gracefully on small screens)
///   • a white rounded "sheet" at the bottom that holds the screen content
///     and scrolls when the keyboard appears.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.children,
    this.showBack = false,
    this.onBack,
    this.footer,
  });

  /// Content of the white bottom sheet (scrolls).
  final List<Widget> children;
  final bool showBack;
  final VoidCallback? onBack;

  /// Optional widget pinned to the very bottom of the white sheet (e.g. a
  /// primary action button). Stays below the scrollable [children].
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    // Extra bottom gap for the lowest button — Android 15+ edge-to-edge nav bar
    // only. 0 on iOS (and Android < 15), so iOS gets no extra spacer.
    final double bottomGap = AppDevice.bottomNavGap;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.authGradient),
        child: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Logo scales with the smaller of width/height so it never
              // overflows on compact devices.
              final double logoSize =
                  (constraints.maxWidth * 0.52).clamp(120.0, 210.0);
              // Header (logo + rings) takes ~47% of the height like the design, so
              // the white sheet fills with the content and the button lands at the
              // bottom. It still shrinks on short viewports (keyboard / small
              // phones) so the whole page scrolls instead of overflowing.
              final double headerHeight =
                  (constraints.maxHeight * 0.47).clamp(160.0, 470.0);
              // Side padding scales with width: tighter on small phones, roomier
              // on large ones.
              final double hPad =
                  (constraints.maxWidth * 0.064).clamp(20.0, 28.0);

              // The WHOLE page (logo + white sheet) scrolls as one unit: it stays
              // fixed/filled when the content fits (minHeight = viewport) and
              // scrolls when it doesn't (small screen / keyboard open) — so the
              // Login button is always reachable.
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      children: [
                        // ---- Header (back button + logo) ----
                        SizedBox(
                          height: headerHeight,
                          child: Stack(
                            children: [
                              if (showBack)
                                Positioned(
                                  top: 4,
                                  left: 4,
                                  child: IconButton(
                                    icon: const Icon(Icons.arrow_back_ios_new,
                                        color: Colors.white, size: 20),
                                    onPressed: onBack ??
                                        () => Navigator.of(context).pop(),
                                  ),
                                ),
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: SflLogo(size: logoSize),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // ---- White content sheet (fills the rest) ----
                        Expanded(
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: context.palette.surface,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(30),
                                topRight: Radius.circular(30),
                              ),
                            ),
                            child: Column(
                              // Stretch so the content + footer (and their
                              // full-width buttons) fill the sheet width.
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    hPad,
                                    20,
                                    hPad,
                                    // No footer → the bottom-most button is the
                                    // last child here, so clear the nav bar.
                                    footer == null ? 20 + bottomGap : 8,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: children,
                                  ),
                                ),
                                // Footer pinned to the bottom of the sheet (only
                                // when the content is short enough to leave room).
                                if (footer != null) ...[
                                  const Spacer(),
                                  Padding(
                                    padding: EdgeInsets.fromLTRB(
                                        hPad, 0, hPad, 20 + bottomGap),
                                    child: footer,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Centered title + subtitle block used at the top of each sheet.
class AuthHeadingText extends StatelessWidget {
  const AuthHeadingText({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: p.title,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            color: p.subtitle,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}
