import 'package:flutter/material.dart';
import '../../data/models/lead_basic_details.dart';
import '../../data/models/lead_item.dart';
import '../../data/repositories/lead_repository.dart';
import '../../theme/app_colors.dart';
import '../application/application_flow_ui.dart';

/// Lead Details — read-only popup opened from the eye icon on a My Leads / All
/// Leads card. Loads `POST /rm/lead-basic-details` ({ leadId }) and shows the
/// Basic + Vehicle details for that lead.
class LeadDetailsScreen extends StatefulWidget {
  const LeadDetailsScreen({super.key, required this.lead});
  final LeadItem lead;

  @override
  State<LeadDetailsScreen> createState() => _LeadDetailsScreenState();
}

class _LeadDetailsScreenState extends State<LeadDetailsScreen> {
  final _repo = LeadRepository();
  bool _loading = true;
  String? _error;
  LeadBasicDetails? _data;

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
      // API keys on the numeric leadId (e.g. 647); lead.id is its string form.
      final leadId = int.tryParse(widget.lead.id.trim()) ?? widget.lead.id;
      final data = await _repo.getLeadBasicDetails(leadId: leadId);
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

  String _v(String s, [String fallback = '—']) => s.trim().isEmpty ? fallback : s;

  // DOB → dd-MM-yyyy (e.g. "16/07/1994" → "16-07-1994"). Handles day-first
  // dd-MM-yyyy / dd/MM/yyyy and yyyy-MM-dd / ISO datetime. Empty → '—'.
  String _fmtDob(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return '—';
    final dmy = RegExp(r'^(\d{1,2})[-/](\d{1,2})[-/](\d{4})').firstMatch(v);
    if (dmy != null) {
      return '${dmy.group(1)!.padLeft(2, '0')}-'
          '${dmy.group(2)!.padLeft(2, '0')}-${dmy.group(3)}';
    }
    final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(v);
    if (iso != null) {
      return '${iso.group(3)}-${iso.group(2)}-${iso.group(1)}';
    }
    return v;
  }

  @override
  Widget build(BuildContext context) {
    return AppFlowScaffold(
      title: 'Lead Details',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _load)
              : _body(),
    );
  }

  Widget _body() {
    final b = _data?.basic;
    final v = _data?.vehicle;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        FlowCard(
          heading: 'Basic Details',
          child: Column(
            children: [
              DetailRow(label: 'Lead ID:', value: _v(b?.leadId ?? '')),
              DetailRow(label: 'Lead Name:', value: _v(b?.leadName ?? '')),
              DetailRow(
                  label: 'Mobile Number:', value: _v(b?.mobileNumber ?? '')),
              // DetailRow(
              //     label: 'Email Address:', value: _v(b?.emailAddress ?? '')),
              DetailRow(
                  label: 'Date of Birth:', value: _fmtDob(b?.dateOfBirth ?? '')),
              DetailRow(label: 'Gender:', value: _v(b?.gender ?? '')),
              DetailRow(label: 'Address:', value: _v(b?.address ?? '')),
            ],
          ),
        ),
        const SizedBox(height: 14),
        FlowCard(
          heading: 'Vehicle Details',
          child: Column(
            children: [
              DetailRow(label: 'OEM:', value: _v(v?.oem ?? '')),
              DetailRow(label: 'Dealer:', value: _v(v?.dealer ?? '')),
              DetailRow(
                  label: 'Vehicle Model:', value: _v(v?.vehicleModel ?? '')),
              DetailRow(
                  label: 'Vehicle Category:',
                  value: _v(v?.vehicleCategory ?? '')),
            ],
          ),
        ),
      ],
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
