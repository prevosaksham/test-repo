import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'more_scaffold.dart';

/// One numbered policy/terms section (heading + body paragraph(s)).
class PolicySection {
  const PolicySection(this.heading, this.body);
  final String heading;
  final String body; // may contain newlines / "• " bullet lines
}

/// Shared layout for the long-form legal screens (Privacy Policy, Terms &
/// Conditions): a heading row with a language selector, then a stack of
/// section cards. Content is static for now (would come from the backend later).
class PolicyScreen extends StatelessWidget {
  const PolicyScreen({
    super.key,
    required this.title,
    required this.sections,
    this.appBarTitle,
    this.language,
    this.onLanguageChanged,
    this.loading = false,
    this.error,
    this.onRetry,
  });

  final String title; // body heading (may be localized)
  final List<PolicySection> sections;
  final String? appBarTitle; // fixed AppBar title (defaults to [title])
  final String? language; // 'en'|'hi'|'mr' — when set the selector is live
  final ValueChanged<String>? onLanguageChanged;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return MoreScaffold(
      title: appBarTitle ?? title,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: p.title,
                  ),
                ),
              ),
              _LanguageSelector(
                  language: language, onChanged: onLanguageChanged),
            ],
          ),
          const SizedBox(height: 14),
          if (loading)
            const Padding(
              padding: EdgeInsets.only(top: 60),
              child: Center(
                  child: CircularProgressIndicator(color: AppColors.purple)),
            )
          else if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Column(
                children: [
                  Text(error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: p.subtitle)),
                  const SizedBox(height: 12),
                  if (onRetry != null)
                    TextButton(onPressed: onRetry, child: const Text('Retry')),
                ],
              ),
            )
          else
            for (final s in sections) ...[
              _SectionCard(section: s),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.section});
  final PolicySection section;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.fieldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.heading,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: p.title,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            section.body,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: p.subtitle,
            ),
          ),
        ],
      ),
    );
  }
}

/// Language selector (en/hi/mr). Live when [onChanged] is provided; otherwise a
/// static English chip.
class _LanguageSelector extends StatelessWidget {
  const _LanguageSelector({this.language, this.onChanged});
  final String? language; // 'en'|'hi'|'mr'
  final ValueChanged<String>? onChanged;

  static const Map<String, String> _labels = {
    'en': 'English',
    'hi': 'Hindi',
    'mr': 'Marathi',
  };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final value = _labels.containsKey(language) ? language! : 'en';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: p.fieldBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.fieldBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          icon: Icon(Icons.keyboard_arrow_down, size: 18, color: p.subtitle),
          dropdownColor: p.cardBg,
          style: TextStyle(fontSize: 13.5, color: p.title),
          items: [
            for (final e in _labels.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged:
              onChanged == null ? null : (v) => onChanged!(v ?? 'en'),
        ),
      ),
    );
  }
}
