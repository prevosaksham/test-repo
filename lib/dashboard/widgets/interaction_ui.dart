import 'package:flutter/material.dart';
import '../../core/device/app_device.dart';
import '../../data/models/lead_item.dart';
import '../../data/models/lead_preview.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_colors.dart';

/// Shared building blocks for the Customer Interaction / Application Process
/// screens — the rounded card, the lead header, and the Exit/Action bottom bar.

Color interactionHex(String hex, Color fallback) {
  var h = hex.replaceAll('#', '').trim();
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  return v == null ? fallback : Color(v);
}

/// Rounded, bordered surface card used throughout the flow.
class InteractionCard extends StatelessWidget {
  const InteractionCard({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsets? padding;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.fieldBorder),
      ),
      child: child,
    );
  }
}

/// Lead summary header (ID + status badge + name + phone + location).
///
/// Two sources: a [LeadItem] (list/detail context) or `getPreview`'s
/// [PreviewLeadDetails] via [LeadHeaderCard.details]. Either way it renders the
/// same card from the resolved fields — no static data.
class LeadHeaderCard extends StatelessWidget {
  const LeadHeaderCard({super.key, required LeadItem this.lead})
      : details = null;
  const LeadHeaderCard.details({super.key, required PreviewLeadDetails this.details})
      : lead = null;

  final LeadItem? lead;
  final PreviewLeadDetails? details;

  String get _leadNo => lead?.leadNo ?? details!.leadNo;
  String get _name => lead?.name ?? details!.name;
  String get _mobile => lead?.mobile ?? details!.mobile;
  String get _location => lead?.location ?? details!.location;
  String get _statusDisplayName =>
      lead?.status.displayName ?? details!.statusDisplayName;
  String get _statusColorHex =>
      lead?.status.colorHex ?? details!.statusColorHex;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final statusColor =
        interactionHex(_statusColorHex, AppColors.chartProgress);
    return InteractionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Lead ID',
                        style: TextStyle(fontSize: 12, color: p.subtitle)),
                    const SizedBox(height: 2),
                    Text(_leadNo.isEmpty ? '—' : _leadNo,
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.purple)),
                  ],
                ),
              ),
              if (_statusDisplayName.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(_statusDisplayName,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: statusColor)),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: p.fieldBorder),
          ),
          Text(_name.isEmpty ? '—' : _name,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: p.title)),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.call, size: 16, color: p.subtitle),
              const SizedBox(width: 5),
              Text(_mobile.isEmpty ? '—' : _mobile,
                  style: TextStyle(fontSize: 14, color: p.subtitle)),
              if (_location.isNotEmpty) ...[
                const SizedBox(width: 14),
                Icon(Icons.location_on_outlined, size: 17, color: p.subtitle),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(_location,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: p.subtitle)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Bottom bar: outlined "Exit" + gradient action button. [enabled] dims the
/// action button (mockup shows a faded button until the step is satisfied).
class InteractionBottomBar extends StatelessWidget {
  const InteractionBottomBar({
    super.key,
    required this.actionLabel,
    required this.onAction,
    this.enabled = true,
    this.onExit,
  });
  final String actionLabel;
  final VoidCallback onAction;
  final bool enabled;
  final VoidCallback? onExit;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      // Extra bottom gap for Android 15+ edge-to-edge nav bar (0 otherwise).
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + AppDevice.bottomNavGap),
      decoration: BoxDecoration(
        color: p.cardBg,
        border: Border(top: BorderSide(color: p.fieldBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                // Exit always returns to Home (clears the application stack), so
                // every screen's Exit lands on the dashboard — not the prev step.
                onPressed: onExit ??
                    () => Navigator.of(context)
                        .pushNamedAndRemoveUntil(AppRoutes.home, (r) => false),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  side: BorderSide(color: p.fieldBorder),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Exit',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: p.title)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Opacity(
                opacity: enabled ? 1 : 0.5,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: AppColors.buttonGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ElevatedButton(
                    onPressed: enabled ? onAction : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      disabledBackgroundColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(actionLabel,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
