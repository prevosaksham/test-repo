import 'package:flutter/material.dart';
import '../../core/network/api_exception.dart';
import '../../data/repositories/policy_repository.dart';
import 'policy_screen.dart';

/// Terms & Conditions — content from `POST /privacy-policy/terms { language }`
/// (en/hi/mr). Defaults to English; the language selector re-fetches.
class TermsConditionsScreen extends StatefulWidget {
  const TermsConditionsScreen({super.key});

  @override
  State<TermsConditionsScreen> createState() => _TermsConditionsScreenState();
}

class _TermsConditionsScreenState extends State<TermsConditionsScreen> {
  final PolicyRepository _repo = PolicyRepository();
  String _lang = 'en'; // default English
  String _title = 'Terms & Conditions';
  List<PolicySection> _sections = const [];
  bool _loading = true;
  String? _error;

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
      final res = await _repo.getTerms(_lang);
      if (!mounted) return;
      setState(() {
        _title = res.title.isNotEmpty ? res.title : 'Terms & Conditions';
        _sections =
            res.sections.map((s) => PolicySection(s.heading, s.body)).toList();
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load the terms & conditions. Please try again.';
        _loading = false;
      });
    }
  }

  void _onLanguageChanged(String code) {
    if (code == _lang) return;
    setState(() => _lang = code);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return PolicyScreen(
      appBarTitle: 'Terms & Conditions',
      title: _title,
      sections: _sections,
      language: _lang,
      onLanguageChanged: _onLanguageChanged,
      loading: _loading,
      error: _error,
      onRetry: _load,
    );
  }
}
