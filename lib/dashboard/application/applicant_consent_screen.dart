import 'package:flutter/material.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/models/consent_item.dart';
import '../../data/models/lead_item.dart';
import '../../data/repositories/application_repository.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_colors.dart';
import '../widgets/interaction_ui.dart';
import 'application_flow_ui.dart';
import 'consent_link_sent_screen.dart';
import 'consent_mode_dialog.dart';
import 'consent_passcode_sent_screen.dart';

/// Step 3 of 5 — in-app (OTP-mode) consent capture. Used for both the applicant
/// and the co-applicant ([isCoApplicant]). Agreeing advances: Applicant →
/// Co-Applicant → Consent Captured. The terms list comes from
/// `GET /consent/list`.
class ApplicantConsentScreen extends StatefulWidget {
  const ApplicantConsentScreen({super.key, required this.lead});
  // Only the lead is passed (the lead id from My Leads). applicationId +
  // applicant/co mobile are fetched here from /application/details — nothing
  // else is passed page-to-page.
  final LeadItem lead;

  @override
  State<ApplicantConsentScreen> createState() => _ApplicantConsentScreenState();
}

class _ApplicantConsentScreenState extends State<ApplicantConsentScreen> {
  final ApplicationRepository _repo = ApplicationRepository();

  bool _agreed = false;
  String _lang = 'English';

  bool _loading = true;
  bool _sending = false; // Send OTP call in progress
  bool _loadingConsents = false; // re-fetching terms after a language change
  String? _error;
  List<ConsentItem> _items = const [];
  String _termsTitle = ''; // Terms header title from the API
  String _termsDesc = ''; // Terms header description from the API

  // Dropdown label → API language code.
  String get _langCode {
    switch (_lang) {
      case 'Hindi':
        return 'hi';
      case 'Marathi':
        return 'mr';
      default:
        return 'en';
    }
  }

  // Everything below is fetched from /application/details on THIS page (nothing
  // is passed in) — applicationId/No + applicant & co-applicant mobile. This
  // feeds the send-otp call + the Passcode Sent screen.
  String _applicationId = '';
  String _applicationNo = '';
  String _appMobile = '';
  String _coMobile = '';

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
      final consent = await _repo.getConsentList(lang: _langCode);
      // Also fetch /application/details for applicationId + applicant/co mobile.
      final d = await _repo.getApplicationDetails(leadId: widget.lead.id);
      _applicationId = d.applicationId;
      _applicationNo = d.applicationNo;
      _appMobile = d.applicant?.phoneNumber ?? '';
      _coMobile = d.coApplicant?.phoneNumber ?? '';
      if (!mounted) return;
      setState(() {
        _items = consent.items;
        _termsTitle = consent.title;
        _termsDesc = consent.description;
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

  // Re-fetch ONLY the terms list in the selected language (on dropdown change).
  // Keeps the already-loaded applicationId/mobiles; shows a small loader over
  // the list. On failure the previous-language terms stay.
  Future<void> _loadConsents() async {
    setState(() => _loadingConsents = true);
    try {
      final consent = await _repo.getConsentList(lang: _langCode);
      if (!mounted) return;
      setState(() {
        _items = consent.items;
        _termsTitle = consent.title;
        _termsDesc = consent.description;
      });
    } catch (_) {
      if (mounted) _snack('Could not load terms in the selected language.');
    } finally {
      if (mounted) setState(() => _loadingConsents = false);
    }
  }

  // "Send" → ask the OTP/LINK mode FIRST, then fire send-otp or send-link.
  // applicationId + mobiles come from /application/details (fetched in _load).
  Future<void> _onSend() async {
    if (_sending) return;
    final mode = await showConsentModeDialog(context); // 'otp' / 'link' / null
    if (mode == null || !mounted) return;
    setState(() => _sending = true);
    try {
      final appId = int.tryParse(_applicationId.trim()) ?? _applicationId;
      final consentIds = _items
          .map((e) => int.tryParse(e.id.trim()) ?? 0)
          .where((id) => id > 0)
          .toList();
      if (mode == 'link') {
        // LINK → send the consent link, then the Link Sent screen.
        final res = await _repo.sendConsentLink(
          applicationId: appId,
          consentIds: consentIds,
          applicantMobile: _appMobile,
          coApplicantMobile: _coMobile,
        );
        debugPrint('send-link response: $res');
        if (!mounted) return;
        final ok =
            res is Map && (res['success'] == true || res['status'] == true);
        final msg = _serverMsg(res);
        if (!ok) {
          _snack(msg ?? 'Could not send the consent link. Please try again.');
          return;
        }
        if (msg != null) _snack(msg, ok: true);
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ConsentLinkSentScreen(
            lead: widget.lead,
            applicationId: _applicationId,
            applicationNo: _applicationNo,
            applicantMobile: _appMobile,
            coApplicantMobile: _coMobile,
            consentIds: consentIds,
          ),
        ));
      } else {
        // OTP → send the passcode, then the Passcode Sent screen.
        final res = await _repo.sendConsentOtp(
          applicationId: appId,
          consentIds: consentIds,
          applicantMobile: _appMobile,
          coApplicantMobile: _coMobile,
        );
        debugPrint('send-otp response: $res');
        if (!mounted) return;
        final ok =
            res is Map && (res['success'] == true || res['status'] == true);
        final msg = _serverMsg(res);
        if (!ok) {
          _snack(msg ?? 'Could not send OTP. Please try again.');
          return;
        }
        // Show the server's success message (jaise LINK me dikhta hai).
        if (msg != null) _snack(msg, ok: true);
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ConsentPasscodeSentScreen(
            lead: widget.lead,
            applicationId: _applicationId,
            applicationNo: _applicationNo,
            applicantMobile: _appMobile,
            coApplicantMobile: _coMobile,
            consentIds: consentIds,
            message: msg ?? '',
          ),
        ));
      }
    } on ApiException catch (e) {
      if (mounted) _snack(e.message);
    } catch (_) {
      if (mounted) _snack('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // The server's message from a consent response (null when none).
  String? _serverMsg(dynamic res) =>
      (res is Map &&
              res['message'] is String &&
              (res['message'] as String).trim().isNotEmpty)
          ? (res['message'] as String).trim()
          : null;

  void _snack(String msg, {bool ok = false}) {
    AppToast.show(context, msg,
        type: ok ? ToastType.success : ToastType.error);
  }

  @override
  Widget build(BuildContext context) {
    return AppFlowScaffold(
      title: 'Applicant and Co-applicant Consent',
      stepText: 'Step 3 of 5',
      // "Exit" + "Send" — enabled only once the list has loaded and the agree
      // box is ticked. "Send" opens the OTP/LINK choice dialog.
      bottomBar: InteractionBottomBar(
        actionLabel: _sending ? 'Sending…' : 'Send',
        enabled: _agreed && _items.isNotEmpty && !_sending,
        onAction: _onSend,
        onExit: () => Navigator.of(context)
            .pushNamedAndRemoveUntil(AppRoutes.home, (r) => false),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    final p = context.palette;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 40, color: p.subtitle),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: p.subtitle)),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _load,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Retry',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: AppColors.primary)),
              ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        _termsTitle.isNotEmpty
                            ? _termsTitle
                            : 'Terms & Conditions',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: p.title)),
                    const SizedBox(height: 4),
                    Text(
                      _termsDesc.isNotEmpty
                          ? _termsDesc
                          : 'Please read the terms and conditions carefully '
                              'before proceeding',
                      style: TextStyle(fontSize: 13, color: p.subtitle),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _langDropdown(),
            ],
          ),
          const SizedBox(height: 14),
          // All terms in ONE scrollable card — every item's full text stays
          // expanded (no accordion). The LAST item (Declaration) is shown with
          // the agree checkbox instead of a number.
          Expanded(
            child: _loadingConsents
                ? const Center(child: CircularProgressIndicator())
                : _consentCard(),
          ),
        ],
      ),
    );
  }

  // The bordered card holding every consent term, scrolling internally.
  Widget _consentCard() {
    final p = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: p.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.fieldBorder),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Scrollbar(
        thumbVisibility: true,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 14),
          itemCount: _items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 18),
          itemBuilder: (ctx, i) {
            final item = _items[i];
            // Last item = Declaration → checkbox row (the agree tick).
            if (i == _items.length - 1) return _declarationItem(item);
            return _consentTextItem(i + 1, item);
          },
        ),
      ),
    );
  }

  // A numbered term: bold title + full body text (always expanded).
  Widget _consentTextItem(int number, ConsentItem item) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$number. ${item.displayName}',
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: p.title)),
        const SizedBox(height: 6),
        Text(item.content,
            style: TextStyle(fontSize: 13, height: 1.5, color: p.subtitle)),
      ],
    );
  }

  // The Declaration term — tappable checkbox + title, then the body text. The
  // checkbox is the agree tick that gates the Send button (_agreed).
  Widget _declarationItem(ConsentItem item) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _agreed = !_agreed),
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: _agreed ? AppColors.purple : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _agreed ? AppColors.purple : p.fieldBorder,
                    width: 1.5,
                  ),
                ),
                child: _agreed
                    ? const Icon(Icons.check, size: 15, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(item.displayName,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: p.title)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(item.content,
            style: TextStyle(fontSize: 13, height: 1.5, color: p.subtitle)),
      ],
    );
  }

  Widget _langDropdown() {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: p.fieldBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.fieldBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _lang,
          isDense: true,
          icon: Icon(Icons.keyboard_arrow_down, size: 18, color: p.subtitle),
          dropdownColor: p.cardBg,
          style: TextStyle(fontSize: 13.5, color: p.title),
          items: const [
            DropdownMenuItem(value: 'English', child: Text('English')),
            DropdownMenuItem(value: 'Hindi', child: Text('Hindi')),
            DropdownMenuItem(value: 'Marathi', child: Text('Marathi')),
          ],
          onChanged: _loadingConsents
              ? null
              : (v) {
                  if (v == null || v == _lang) return;
                  setState(() => _lang = v);
                  _loadConsents(); // reload terms in the chosen language
                },
        ),
      ),
    );
  }
}

