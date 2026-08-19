import 'package:flutter/material.dart';
import '../../core/constants/app_assets.dart';
import '../../core/widgets/app_icon.dart';
import '../../data/models/lead_details.dart';
import '../../theme/app_colors.dart';

/// Timeline tab — the stages from `data.timeline` shown as a clickable vertical
/// stepper on the left and an "Actions & Information" panel on the right whose
/// content follows the tapped/selected step. Only the data the API sends is
/// shown (stage name, status and description).
class ViewLeadTimelineTab extends StatefulWidget {
  const ViewLeadTimelineTab({super.key, required this.stages});

  final List<LeadTimelineStage> stages;

  @override
  State<ViewLeadTimelineTab> createState() => _ViewLeadTimelineTabState();
}

class _ViewLeadTimelineTabState extends State<ViewLeadTimelineTab> {
  late int _selected = _defaultSelection();

  // Default to the current (in-progress) step, else the last completed one,
  // else the first step.
  int _defaultSelection() {
    final s = widget.stages;
    final cur = s.indexWhere((e) => e.isCurrent);
    if (cur >= 0) return cur;
    final lastDone = s.lastIndexWhere((e) => e.isDone);
    if (lastDone >= 0) return lastDone;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.stages.isEmpty) {
      final p = context.palette;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('No timeline available',
              style: TextStyle(fontSize: 13.5, color: p.subtitle)),
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 5, child: _stepper()),
        const SizedBox(width: 12),
        Expanded(flex: 6, child: _actionsCard()),
      ],
    );
  }

  // ---- Left: stepper ----
  Widget _stepper() {
    return Column(
      children: [
        for (var i = 0; i < widget.stages.length; i++)
          _StepRow(
            number: i + 1,
            stage: widget.stages[i],
            selected: i == _selected,
            isLast: i == widget.stages.length - 1,
            onTap: () => setState(() => _selected = i),
          ),
      ],
    );
  }

  // ---- Right: actions & information ----
  Widget _actionsCard() {
    final p = context.palette;
    final stage = widget.stages[_selected];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.fieldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Actions & Information',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: p.title)),
          const SizedBox(height: 12),
          _statusPill(stage),
          // Action Date & Time — from the stage's details.actionAt.
          if (stage.actionAt.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            _infoTile(
              icon: AppAssets.calendar,
              label: 'Action Date & Time',
              value: _fmtActionAt(stage.actionAt),
            ),
          ],
          // Completed By — from the stage's details.completedBy.name.
          if (stage.completedByName.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            _infoTile(
              icon: AppAssets.circleUser,
              label: 'Completed By',
              value: stage.completedByName,
            ),
          ],
          // Details — from the stage's details.desc.
          if (stage.desc.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            _infoTile(
              icon: AppAssets.document,
              label: 'Details',
              value: stage.desc,
            ),
          ],
          // Nothing has happened on this stage yet (details = null).
          if (stage.actionAt.trim().isEmpty &&
              stage.completedByName.trim().isEmpty &&
              stage.desc.trim().isEmpty) ...[
            const SizedBox(height: 12),
            Text('No details available yet.',
                style: TextStyle(fontSize: 13, color: p.subtitle)),
          ],
        ],
      ),
    );
  }

  // "2026-06-24T06:17:33.348Z" → "24 Jun 2026 11:47 AM" (device-local time).
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  String _fmtActionAt(String raw) {
    final dt = DateTime.tryParse(raw.trim());
    if (dt == null) return raw.trim();
    final l = dt.toLocal();
    final h12 = l.hour % 12 == 0 ? 12 : l.hour % 12;
    final ampm = l.hour < 12 ? 'AM' : 'PM';
    return '${l.day.toString().padLeft(2, '0')} ${_months[l.month - 1]} '
        '${l.year} ${h12.toString().padLeft(2, '0')}:'
        '${l.minute.toString().padLeft(2, '0')} $ampm';
  }

  Widget _statusPill(LeadTimelineStage stage) {
    final color = _stateColor(context, stage);
    final icon = stage.isRejected
        ? Icons.cancel
        : stage.isDone
            ? Icons.check_circle
            : stage.isLocked
                ? Icons.lock_outline
                : Icons.timelapse;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(stage.statusLabel,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color)),
          ],
        ),
      ),
    );
  }

  Widget _infoTile({
    required String icon,
    required String label,
    required String value,
  }) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: p.fieldBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.fieldBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.purple.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: AppIcon(icon, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11.5, color: p.subtitle)),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                        fontSize: 13.5,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        color: p.title)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Colour for a stage's state: red when rejected, green when done, purple when
/// in progress, grey when locked/pending.
Color _stateColor(BuildContext context, LeadTimelineStage stage) {
  if (stage.isRejected) return AppColors.statusRed;
  if (stage.isDone) return AppColors.success;
  if (stage.isCurrent) return AppColors.purple;
  return context.palette.subtitle;
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.number,
    required this.stage,
    required this.selected,
    required this.isLast,
    required this.onTap,
  });
  final int number;
  final LeadTimelineStage stage;
  final bool selected;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final done = stage.isDone;
    final current = stage.isCurrent;
    final locked = stage.isLocked;
    final rejected = stage.isRejected;

    final Widget circle = Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: current ? AppColors.buttonGradient : null,
        color: rejected
            ? AppColors.statusRed
            : done
                ? AppColors.success
                : current
                    ? null
                    : p.surface,
        border: (done || current || rejected)
            ? null
            : Border.all(color: p.fieldBorder, width: 1.5),
      ),
      child: rejected
          ? const Icon(Icons.close, size: 14, color: Colors.white)
          : done
              ? const Icon(Icons.check, size: 14, color: Colors.white)
              : locked
                  ? Icon(Icons.lock_outline, size: 12, color: p.subtitle)
                  : Text('$number',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: current ? Colors.white : p.subtitle)),
    );

    return GestureDetector(
      // Locked steps aren't clickable.
      onTap: locked ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: locked ? 0.6 : 1,
        child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 24,
              child: Column(
                children: [
                  circle,
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2,
                        color: done ? AppColors.success : p.fieldBorder,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                margin: EdgeInsets.only(bottom: isLast ? 0 : 18),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.purple.withValues(alpha: 0.08)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  stage.stageName,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.25,
                    fontWeight: (done || current || rejected || selected)
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: (done || current || rejected || selected)
                        ? p.title
                        : p.subtitle,
                  ),
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
