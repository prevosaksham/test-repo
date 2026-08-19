import 'package:flutter/material.dart';
import '../../data/models/financial_approval.dart';
import '../../data/models/lead_item.dart';
import '../../data/repositories/lead_repository.dart';
import '../../theme/app_colors.dart';
import 'application_flow_ui.dart';
import 'generated_document_card.dart';

/// Financial Documents — the generated documents (Sanction Letter, Loan
/// Agreement, KFS, Repayment Schedule) with Preview / Download, opened from the
/// eSign screen's "View Documents". Data from `POST /field-verification/details`.
class FinancialDocumentsScreen extends StatefulWidget {
  const FinancialDocumentsScreen({super.key, required this.lead});
  final LeadItem lead;

  @override
  State<FinancialDocumentsScreen> createState() =>
      _FinancialDocumentsScreenState();
}

class _FinancialDocumentsScreenState extends State<FinancialDocumentsScreen> {
  final _repo = LeadRepository();
  bool _loading = true;
  String? _error;
  FinancialApproval? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _repo.getFinancialApproval(leadId: widget.lead.id);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('ApiException: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (_loading) {
      return const AppFlowScaffold(
        title: 'Financial Documents',
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return AppFlowScaffold(
        title: 'Financial Documents',
        body: _ErrorView(message: _error!, onRetry: _load),
      );
    }
    final docs = _data?.documents ?? const [];
    final appId = _data?.applicant.id ?? '';
    return AppFlowScaffold(
      title: 'Financial Documents',
      body: docs.isEmpty
          ? Center(
              child: Text('No documents available',
                  style: TextStyle(fontSize: 14, color: p.subtitle)),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemBuilder: (_, i) => GeneratedDocumentCard(
                doc: docs[i],
                applicationId: appId,
                greenWhenGenerated: true,
              ),
            ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: p.subtitle),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: p.subtitle)),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Retry',
                  style: TextStyle(color: AppColors.primary)),
            ),
          ],
        ),
      ),
    );
  }
}
