import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// A rounded grey panel that wraps a titled section (Today Task, charts, …).
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child, this.padding});
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

/// One task row inside the Home "Today Task" card: Lead ID + Name header, a
/// divider, then label/value lines.
class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.leadId,
    required this.leadName,
    required this.rows,
    this.alignValueToName = false,
  });
  final String leadId;
  final String leadName;
  final List<(String, String)> rows;
  // true → each row uses the SAME two-column split as the header, so the value
  // lines up exactly under "Lead Name" (label sits under "Lead ID"). false → the
  // classic label-on-left (fixed width), value-on-right layout.
  final bool alignValueToName;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.fieldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _kv('Lead ID', leadId,
                    valueColor: AppColors.purple, valueBold: true),
              ),
              Expanded(
                child: _kv('Lead Name', leadName,
                    valueColor: p.title, valueBold: true),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: p.fieldBorder),
          ),
          // A Table with an equal 50/50 flex split — the label column matches
          // "Lead ID" and the value column matches "Lead Name", so every value
          // lines up exactly under the name (no static widths, fully expandable).
          Table(
            columnWidths: const {0: FlexColumnWidth(), 1: FlexColumnWidth()},
            defaultVerticalAlignment: TableCellVerticalAlignment.top,
            children: [
              for (final r in rows)
                TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6, right: 12),
                      child: Text(r.$1,
                          style: TextStyle(fontSize: 13, color: p.subtitle)),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(r.$2,
                          style: TextStyle(
                              fontSize: 13,
                              color: p.title,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kv(String label, String value,
      {required Color valueColor, bool valueBold = false}) {
    return Builder(builder: (context) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12, color: context.palette.subtitle)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 14,
                  color: valueColor,
                  fontWeight: valueBold ? FontWeight.w700 : FontWeight.w500)),
        ],
      );
    });
  }
}
