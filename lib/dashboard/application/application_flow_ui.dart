import 'package:flutter/material.dart';
import '../../core/constants/app_assets.dart';
import '../../core/device/app_device.dart';
import '../../core/widgets/app_icon.dart';
import '../../theme/app_colors.dart';

/// Page chrome for the Application Details flow (Steps 2–5): back-chevron
/// centered-title AppBar, a centered "Step X of 5" line, a scrollable body and
/// an optional pinned bottom bar.
class AppFlowScaffold extends StatelessWidget {
  const AppFlowScaffold({
    super.key,
    required this.title,
    this.stepText,
    required this.body,
    this.bottomBar,
    this.lockBack = false,
  });

  final String title;
  final String? stepText; // e.g. "Step 2 of 5" (hidden when null/empty)
  final Widget body;
  final Widget? bottomBar;
  // Post-OTP pages (passcode entry → submit): once the OTP is sent/verified the
  // RM can't return to an earlier step. true hides the top back arrow AND blocks
  // the hardware/gesture back — the only way out is the bottom "Exit" (→ Home).
  final bool lockBack;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final scaffold = Scaffold(
      backgroundColor: p.surface,
      appBar: AppBar(
        backgroundColor: p.cardBg,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: !lockBack,
        leading: lockBack
            ? null
            : IconButton(
                icon: Icon(Icons.arrow_back_ios_new, size: 20, color: p.title),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: p.title,
          ),
        ),
      ),
      body: Column(
        children: [
          if (stepText != null && stepText!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Center(
              child: Text(
                stepText!,
                style: TextStyle(fontSize: 13, color: p.subtitle),
              ),
            ),
            const SizedBox(height: 4),
          ],
          Expanded(child: body),
          ?bottomBar,
        ],
      ),
    );
    // Block the hardware/gesture back when locked.
    return lockBack ? PopScope(canPop: false, child: scaffold) : scaffold;
  }
}

/// A rounded, bordered surface card with an optional bold section heading.
class FlowCard extends StatelessWidget {
  const FlowCard({
    super.key,
    this.heading,
    this.headingTrailing,
    required this.child,
  });
  final String? heading;
  final Widget? headingTrailing; // e.g. a "Verified" pill on the right
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.fieldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (heading != null) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    heading!,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: p.title,
                    ),
                  ),
                ),
                ?headingTrailing,
              ],
            ),
            const SizedBox(height: 14),
          ],
          child,
        ],
      ),
    );
  }
}

/// "Label : Value" row. [sublabel] is the small grey note under the label
/// (e.g. "(as per PAN)"); [valueWidget] overrides the plain text value.
class DetailRow extends StatelessWidget {
  const DetailRow({
    super.key,
    required this.label,
    this.sublabel,
    this.value,
    this.valueWidget,
    this.labelWidth = 118,
  });
  final String label;
  final String? sublabel;
  final String? value;
  final Widget? valueWidget;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: labelWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 13.5, color: p.subtitle),
                ),
                if (sublabel != null)
                  Text(
                    sublabel!,
                    style: TextStyle(fontSize: 11.5, color: p.hint),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: valueWidget ??
                Text(
                  // Empty / null value → show a dash.
                  (value == null || value!.trim().isEmpty) ? '—' : value!,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
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

/// Bordered, read-only field used for the editable-looking values in the
/// details cards (Mobile Number, dropdowns).
class FlowFieldBox extends StatelessWidget {
  const FlowFieldBox({super.key, required this.text, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: p.fieldBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.fieldBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: p.title,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Big circular success badge with a small green check overlay (used on the
/// Consent / KYC / Submit success screens).
class SuccessBadge extends StatelessWidget {
  const SuccessBadge({super.key, this.child, this.bigCheck = false});

  /// Inner icon (e.g. a custom SVG). When null and [bigCheck] is true, shows a
  /// large filled green check (KYC / Consent-captured style).
  final Widget? child;
  final bool bigCheck;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      height: 92,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.purple.withValues(alpha: 0.10),
            ),
          ),
          if (bigCheck)
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.success,
              ),
              child: const Icon(Icons.check, size: 30, color: Colors.white),
            )
          else ...[
            child ?? const SizedBox.shrink(),
            Positioned(
              right: 6,
              bottom: 6,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.success,
                  border: Border.all(color: context.palette.surface, width: 2),
                ),
                child: const Icon(Icons.check, size: 13, color: Colors.white),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Small status pill with a leading icon (e.g. "Consent Captured"). Defaults to
/// green + a check; pass [color]/[icon] for other states (e.g. red "Not
/// Captured").
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.text, this.color, this.icon});
  final String text;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon ?? Icons.check_circle, size: 14, color: c),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: c,
            ),
          ),
        ],
      ),
    );
  }
}

/// Stacked "Agree" (gradient) + "Disagree" (outlined) bottom bar for the
/// consent screens. [enabled] dims the Agree button until the box is ticked.
class ConsentBottomBar extends StatelessWidget {
  const ConsentBottomBar({
    super.key,
    required this.onAgree,
    required this.onDisagree,
    this.enabled = true,
  });
  final VoidCallback onAgree;
  final VoidCallback onDisagree;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      // Extra bottom gap for Android 15+ edge-to-edge nav bar (0 otherwise).
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + AppDevice.bottomNavGap),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.fieldBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Opacity(
              opacity: enabled ? 1 : 0.5,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppColors.buttonGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ElevatedButton(
                  onPressed: enabled ? onAgree : null,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    disabledBackgroundColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Agree',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: onDisagree,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Disagree',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary)),
            ),
          ],
        ),
      ),
    );
  }
}

/// A document tile: a thumbnail placeholder (no preview asset available) above a
/// row with a doc icon, label and (optionally) a green verified check.
class DocThumbTile extends StatelessWidget {
  const DocThumbTile({
    super.key,
    required this.label,
    this.sublabel,
    this.verified = false,
  });
  final String label;
  final String? sublabel; // e.g. "(Front)"
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: p.fieldBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.fieldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.purple.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.image_outlined, size: 28, color: p.iconGrey),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              AppIcon(AppAssets.document, size: 18, color: AppColors.purple),
              const SizedBox(width: 6),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: label,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: p.title),
                      ),
                      if (sublabel != null)
                        TextSpan(
                          text: ' $sublabel',
                          style: TextStyle(fontSize: 11.5, color: p.subtitle),
                        ),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (verified) ...[
                const SizedBox(width: 4),
                const Icon(Icons.check_circle,
                    size: 18, color: AppColors.success),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// A 2-column grid of [DocThumbTile]s (shrink-wrapped for use inside a ListView).
class DocThumbGrid extends StatelessWidget {
  const DocThumbGrid({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 0.95,
      children: children,
    );
  }
}
