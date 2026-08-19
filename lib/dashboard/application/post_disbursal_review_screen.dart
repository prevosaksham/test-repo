import 'dart:io';
import 'package:flutter/material.dart';
import '../../data/models/financial_approval.dart';
import '../../data/models/lead_item.dart';
import '../../data/models/person_detail.dart';
import '../../data/repositories/application_repository.dart';
import '../../data/repositories/lead_repository.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_colors.dart';
import '../widgets/interaction_ui.dart';
import 'application_flow_ui.dart';

/// Post-Disbursal Conditions — review step shown AFTER the documents are
/// submitted on [PostDisbursalConditionsScreen]. Renders the two uploaded
/// documents (RC Book, Driving License) with the details read off them, and
/// carries the final `postDisbursementSubmit` call.
///
/// Details currently come from the existing APIs: the vehicle block from
/// `/field-verification/details` (`assetDetails`) and the licence block from
/// `/application/details` (`applicant`). Registration Number / Registration Date
/// are not in either response yet — they show "—" until the new post-disbursal
/// API lands, at which point only [_load] needs to change.
class PostDisbursalReviewScreen extends StatefulWidget {
  const PostDisbursalReviewScreen({
    super.key,
    required this.lead,
    required this.stageId,
    required this.applicationId,
    this.rcBookPath = '',
    this.licensePath = '',
  });
  final LeadItem lead;
  final String stageId;
  final String applicationId;
  // Local paths of the files just uploaded — used for the thumbnails.
  final String rcBookPath;
  final String licensePath;

  @override
  State<PostDisbursalReviewScreen> createState() =>
      _PostDisbursalReviewScreenState();
}

class _PostDisbursalReviewScreenState extends State<PostDisbursalReviewScreen> {
  final _appRepo = ApplicationRepository();
  final _leadRepo = LeadRepository();

  bool _loading = true;
  bool _submitting = false;
  AssetDetails? _asset; // vehicle block
  PersonDetail? _applicant; // licence block

  @override
  void initState() {
    super.initState();
    _load();
  }

  // Details for both blocks. A failure here is not fatal — the rows fall back to
  // "—" and the RM can still submit.
  Future<void> _load() async {
    try {
      final approval =
          await _leadRepo.getFinancialApproval(leadId: widget.lead.id);
      final details =
          await _appRepo.getApplicationDetails(leadId: widget.lead.id);
      if (!mounted) return;
      setState(() {
        _asset = approval.assetDetails;
        _applicant = details.applicant;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: error ? AppColors.statusRed : AppColors.success,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // Final submit for the post-disbursal stage → Home on success.
  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final appId = int.tryParse(widget.applicationId) ?? widget.applicationId;
      final stageId = int.tryParse(widget.stageId) ?? widget.stageId;
      final res = await _appRepo.postDisbursementSubmit(
        applicationId: appId,
        stageId: stageId,
      );
      if (!mounted) return;
      final ok = res is Map && (res['success'] == true || res['status'] == true);
      final msg = (res is Map &&
              res['message'] is String &&
              (res['message'] as String).trim().isNotEmpty)
          ? (res['message'] as String).trim()
          : (ok ? 'Submitted successfully' : 'Could not submit');
      if (!ok) {
        _snack(msg, error: true);
        return;
      }
      _snack(msg);
      Navigator.of(context)
          .pushNamedAndRemoveUntil(AppRoutes.home, (r) => false);
    } catch (e) {
      _snack(e.toString().replaceFirst('ApiException: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  static String _dash(String v) => v.trim().isEmpty ? '—' : v.trim();

  // ISO date → "20/02/2030". Anything else is shown as-is.
  static String _slashDate(String v) {
    final dt = DateTime.tryParse(v.trim());
    if (dt == null) return _dash(v);
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    return '$d/$m/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AppFlowScaffold(
        title: 'Post-Disbursal Conditions',
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final p = context.palette;
    final a = _asset;
    final app = _applicant;

    return AppFlowScaffold(
      title: 'Post-Disbursal Conditions',
      bottomBar: InteractionBottomBar(
        actionLabel: 'Submit',
        enabled: !_submitting,
        onAction: _submit,
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            children: [
              FlowCard(
                heading: 'Uploaded Documents',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionTitle('Vehicle Details'),
                    const SizedBox(height: 10),
                    _DocThumb(label: 'RC Book', path: widget.rcBookPath),
                    const SizedBox(height: 12),
                    DetailRow(label: 'Owner Name:', value: _dash(a?.ownerName ?? '')),
                    // Registration Number / Date are not in the current APIs.
                    const DetailRow(label: 'Registration Number:', value: '—'),
                    const DetailRow(label: 'Registration Date:', value: '—'),
                    DetailRow(
                        label: 'Chassis Number:',
                        value: _dash(a?.chassisNumber ?? '')),
                    DetailRow(
                        label: 'Engine / Motor Serial Number:',
                        value: _dash(a?.engineNumber ?? '')),
                    DetailRow(
                        label: 'Manufacturer :',
                        value: _dash(a?.manufacturerName ?? '')),
                    const SizedBox(height: 6),
                    Divider(color: p.fieldBorder, height: 24),
                    _SectionTitle('Driving License'),
                    const SizedBox(height: 10),
                    _DocThumb(
                        label: 'Driving License', path: widget.licensePath),
                    const SizedBox(height: 12),
                    DetailRow(
                        label: 'Driving License Number:',
                        value: _dash(app?.dlNumber ?? '')),
                    DetailRow(
                        label: 'DL Expiry Date:',
                        value: _slashDate(app?.dlValidityDate ?? '')),
                    DetailRow(
                        label: 'DL Issuing RTO:',
                        value: _dash(app?.dlIssueRTO ?? '')),
                  ],
                ),
              ),
            ],
          ),
          if (_submitting)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x55000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Vehicle Details" / "Driving License" sub-heading inside the card.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
          color: context.palette.title,
        ),
      ),
    );
  }
}

/// The uploaded file's preview: the image itself (or a doc icon for a PDF) with
/// the document's name in a row underneath.
class _DocThumb extends StatelessWidget {
  const _DocThumb({required this.label, required this.path});
  final String label;
  final String path;

  bool get _isImage {
    final p = path.toLowerCase();
    return p.endsWith('.jpg') || p.endsWith('.jpeg') || p.endsWith('.png');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: 150,
        decoration: BoxDecoration(
          color: p.fieldBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: p.fieldBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 84,
              width: double.infinity,
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(9)),
                child: _isImage && File(path).existsSync()
                    ? Image.file(File(path), fit: BoxFit.cover)
                    : ColoredBox(
                        color: AppColors.purple.withValues(alpha: 0.06),
                        child: Icon(Icons.description_outlined,
                            size: 28, color: p.iconGrey),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.description,
                      size: 16, color: AppColors.purple),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: p.title),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
