import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/constants/app_assets.dart';
import '../../core/widgets/app_icon.dart';
import '../../data/models/financial_approval.dart';
import '../../data/repositories/lead_repository.dart';
import '../../data/services/download_channel.dart';
import '../../theme/app_colors.dart';

/// One generated-document card: icon + name + status pill, then the
/// "Generated on …" line with Preview (view PDF) / Download (save PDF) actions.
///
/// Shared by the Loan Approved and Financial Documents screens.
/// [greenWhenGenerated] = true colours a "Generated" status green too (used on
/// the Financial Documents screen); otherwise only "Signed" is green.
class GeneratedDocumentCard extends StatefulWidget {
  const GeneratedDocumentCard({
    super.key,
    required this.doc,
    required this.applicationId,
    this.greenWhenGenerated = false,
  });
  final GeneratedDocument doc;
  final String applicationId;
  final bool greenWhenGenerated;

  @override
  State<GeneratedDocumentCard> createState() => _GeneratedDocumentCardState();
}

class _GeneratedDocumentCardState extends State<GeneratedDocumentCard> {
  final _repo = LeadRepository();
  bool _previewing = false;
  bool _downloading = false;

  GeneratedDocument get doc => widget.doc;

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _err(Object e) => e.toString().replaceFirst('ApiException: ', '');

  // Preview → fetch the PDF and open it in the in-app viewer.
  Future<void> _preview() async {
    if (_previewing || _downloading) return;
    setState(() => _previewing = true);
    try {
      // 1) inline base64 (server sends the whole PDF in `url`/`fileData`) →
      //    decode directly, no network (avoids HTTP 414 URI-Too-Long).
      // 2) real http url → fetch it.
      // 3) neither → the applicationId + documentType preview API.
      final inline = doc.inlineBytes;
      final bytes = inline ??
          (doc.hasHttpUrl
              ? await _repo.documentBytesFromUrl(doc.url.trim())
              : await _repo.previewDocument(
                  applicationId: widget.applicationId,
                  documentType: doc.documentCode));
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/${doc.documentCode}_preview.pdf');
      await f.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _PdfViewerScreen(
            path: f.path, title: doc.name.isEmpty ? 'Document' : doc.name),
      ));
    } catch (e) {
      _toast(_err(e));
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  // Download → fetch the PDF and save it to the device.
  Future<void> _download() async {
    if (_previewing || _downloading) return;
    setState(() => _downloading = true);
    try {
      // Inline base64 → decode; real http url → fetch; else the download API.
      final inline = doc.inlineBytes;
      final bytes = inline ??
          (doc.hasHttpUrl
              ? await _repo.documentBytesFromUrl(doc.url.trim())
              : await _repo.downloadDocument(
                  applicationId: widget.applicationId,
                  documentType: doc.documentCode));
      final safe = (doc.name.isEmpty ? doc.documentCode : doc.name)
          .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
      final name = '$safe.pdf';
      if (Platform.isAndroid) {
        try {
          final loc = await DownloadChannel.savePdf(filename: name, bytes: bytes);
          _toast(loc != null ? 'Saved to $loc' : 'Saved to Download folder');
        } on MissingPluginException {
          final dir = await getApplicationDocumentsDirectory();
          final f = File('${dir.path}/$name');
          await f.writeAsBytes(bytes, flush: true);
          _toast('Saved to app storage: ${f.path}\n'
              '(reinstall the app to save into the Downloads folder)');
        }
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final f = File('${dir.path}/$name');
        await f.writeAsBytes(bytes, flush: true);
        _toast('Saved to ${f.path}');
      }
    } catch (e) {
      _toast(_err(e));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
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
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.purple.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: AppIcon(AppAssets.document,
                    size: 20, color: AppColors.purple),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(doc.name.isEmpty ? '—' : doc.name,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: p.title)),
              ),
              const SizedBox(width: 8),
              _DocStatusPill(
                  status: doc.status,
                  greenWhenGenerated: widget.greenWhenGenerated),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: p.fieldBorder),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'Generated on\n'),
                      TextSpan(
                        text: doc.generatedOnDateLabel.isEmpty
                            ? '—'
                            : doc.generatedOnDateLabel,
                        style: TextStyle(color: p.title),
                      ),
                    ],
                  ),
                  style:
                      TextStyle(fontSize: 12.5, height: 1.4, color: p.subtitle),
                ),
              ),
              const SizedBox(width: 10),
              _PreviewButton(busy: _previewing, onTap: _preview),
              const SizedBox(width: 8),
              _DownloadButton(busy: _downloading, onTap: _download),
            ],
          ),
        ],
      ),
    );
  }
}

/// Status pill — green for "Signed" (and "Generated" when [greenWhenGenerated]);
/// amber/yellow for every other status ("eSign Pending", "Pending").
class _DocStatusPill extends StatelessWidget {
  const _DocStatusPill(
      {required this.status, this.greenWhenGenerated = false});
  final String status;
  final bool greenWhenGenerated;

  @override
  Widget build(BuildContext context) {
    final text = status.trim().isEmpty ? 'Pending' : status;
    final s = text.trim().toLowerCase();
    final green = s == 'signed' || (greenWhenGenerated && s == 'generated');
    final color = green ? AppColors.success : AppColors.chartProgress;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 11.5, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

/// Outlined orange "Preview" button (spinner while loading).
class _PreviewButton extends StatelessWidget {
  const _PreviewButton({required this.busy, required this.onTap});
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: busy ? null : onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        side: const BorderSide(color: AppColors.primary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: busy
          ? const SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.primary),
            )
          : const Text('Preview',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary)),
    );
  }
}

/// Gradient orange "Download" button (spinner while loading).
class _DownloadButton extends StatelessWidget {
  const _DownloadButton({required this.busy, required this.onTap});
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppColors.buttonGradient,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ElevatedButton(
        onPressed: busy ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: busy
            ? const SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Text('Download',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
      ),
    );
  }
}

/// Fullscreen in-app PDF viewer (opened by Preview).
class _PdfViewerScreen extends StatefulWidget {
  const _PdfViewerScreen({required this.path, required this.title});
  final String path;
  final String title;

  @override
  State<_PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<_PdfViewerScreen> {
  bool _error = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(widget.title, style: const TextStyle(fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: _error
          ? const Center(
              child: Text('Could not open this PDF',
                  style: TextStyle(color: Colors.white70)),
            )
          : PDFView(
              filePath: widget.path,
              swipeHorizontal: false,
              onError: (_) {
                if (mounted) setState(() => _error = true);
              },
            ),
    );
  }
}
