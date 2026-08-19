import 'package:flutter/material.dart';
import '../../core/device/app_device.dart';
import '../../data/models/lead_item.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_colors.dart';
import 'application_flow_ui.dart';

/// Financial Approval stage — "Loan Approval Pending" status. The Credit Officer
/// hasn't approved yet, so the only action here is Exit (→ Home). Static
/// placeholder.
class FinancialApprovalScreen extends StatelessWidget {
  const FinancialApprovalScreen({super.key, required this.lead});
  final LeadItem lead;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppFlowScaffold(
      title: 'Financial Approval',
      bottomBar: _ExitBar(
        onExit: () => Navigator.of(context)
            .pushNamedAndRemoveUntil(AppRoutes.home, (r) => false),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 40, 24, 16),
        children: [
          Center(
            child: Container(
              width: 92,
              height: 92,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.purple.withValues(alpha: 0.10),
              ),
              child: Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.chartProgress,
                ),
                child: const Icon(Icons.priority_high,
                    size: 30, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              'Loan Approval Pending',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: p.title,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              'Awaiting Credit Officer Approval to proceed with Field '
              'Investigation',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.5, color: p.subtitle),
            ),
          ),
        ],
      ),
    );
  }
}

/// Single full-width outlined "Exit" bottom bar (→ Home).
class _ExitBar extends StatelessWidget {
  const _ExitBar({required this.onExit});
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + AppDevice.bottomNavGap),
      decoration: BoxDecoration(
        color: p.cardBg,
        border: Border(top: BorderSide(color: p.fieldBorder)),
      ),
      child: SafeArea(
        top: false,
        child: OutlinedButton(
          onPressed: onExit,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            side: BorderSide(color: p.fieldBorder),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text('Exit',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: p.title)),
        ),
      ),
    );
  }
}
