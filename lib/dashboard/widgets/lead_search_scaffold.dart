import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/models/lead_item.dart';
import '../../data/repositories/lead_repository.dart';
import '../../theme/app_colors.dart';
import 'dashboard_header.dart';

/// Wraps a dashboard tab's body with the shared header + a lead-search overlay.
///
/// Any page that wants the "search a lead from anywhere" behaviour just wraps
/// its content in this: typing a Lead ID / name in the header hits `/rm/list`
/// and shows the matching leads (lead number + name) in an overlay over the
/// page. Tapping a result is a simple click for now (wire detail later via
/// [onLeadTap]).
class LeadSearchScaffold extends StatefulWidget {
  const LeadSearchScaffold({
    super.key,
    required this.body,
    this.showFilter = false,
    this.showProfile = true,
    this.title,
    this.onBack,
    this.onFilter,
    this.onLeadTap,
    this.committedQuery = '',
    this.onClearList,
  });

  final Widget body;
  final bool showFilter;
  // Hide the avatar + welcome name row in the header (View All screen).
  final bool showProfile;
  // Title shown in place of the profile row when [showProfile] is false.
  final String? title;
  // When set, a back arrow is shown before [title].
  final VoidCallback? onBack;
  final VoidCallback? onFilter;
  final ValueChanged<LeadItem>? onLeadTap;

  /// The list's currently-applied search term (e.g. the Lead ID picked from a
  /// search result). Shown in the field so the user sees the active filter.
  final String committedQuery;

  /// Called when the field is cleared (X / tap-outside-then-clear) — the host
  /// uses it to reload the full, unfiltered list.
  final VoidCallback? onClearList;

  @override
  State<LeadSearchScaffold> createState() => _LeadSearchScaffoldState();
}

class _LeadSearchScaffoldState extends State<LeadSearchScaffold> {
  final LeadRepository _leadRepo = LeadRepository();
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  List<LeadItem> _results = const [];
  bool _searching = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = widget.committedQuery;
  }

  @override
  void didUpdateWidget(covariant LeadSearchScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reflect the committed filter (e.g. after picking a search result) in the
    // field — unless the user is actively typing a new search. Compares against
    // the field text (not oldWidget) so it stays hot-reload safe.
    if (_query.isEmpty && _searchCtrl.text != widget.committedQuery) {
      _searchCtrl.text = widget.committedQuery;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Clear the field + results, close the overlay, and ask the host to reload
  /// the full list (the X button / "cancel").
  void _clearSearch() {
    _debounce?.cancel();
    _searchCtrl.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _query = '';
      _results = const [];
      _searching = false;
    });
    widget.onClearList?.call();
  }

  /// Just close the overlay (tap-outside / after picking a result) and revert
  /// the field to the committed filter — does NOT reset the list.
  void _closeOverlay() {
    _debounce?.cancel();
    FocusScope.of(context).unfocus();
    setState(() {
      _query = '';
      _results = const [];
      _searching = false;
      _searchCtrl.text = widget.committedQuery;
    });
  }

  void _onSearchChanged(String q) {
    setState(() => _query = q);
    _debounce?.cancel();
    final term = q.trim();
    if (term.isEmpty) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _runSearch(term),
    );
  }

  Future<void> _runSearch(String term) async {
    try {
      final page = await _leadRepo.getLeads(page: 1, limit: 10, search: term);
      if (!mounted || term != _query.trim()) return; // ignore stale results
      setState(() {
        _results = page.items;
        _searching = false;
      });
    } catch (_) {
      if (!mounted || term != _query.trim()) return;
      setState(() {
        _results = const [];
        _searching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DashboardHeader(
          showSearch: true,
          showFilter: widget.showFilter,
          showProfile: widget.showProfile,
          title: widget.title,
          onBack: widget.onBack,
          onFilter: widget.onFilter,
          onSearchChanged: _onSearchChanged,
          searchController: _searchCtrl,
          onSearchClear: _clearSearch,
        ),
        Expanded(
          child: Stack(
            children: [widget.body, if (_query.trim().isNotEmpty) _overlay()],
          ),
        ),
      ],
    );
  }

  Widget _overlay() {
    final p = context.palette;
    // Background close is a SEPARATE layer BEHIND the card, so taps on the
    // result items hit their InkWell directly (the close GestureDetector no
    // longer wraps them and can't swallow the tap).
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _closeOverlay, // tap outside the card → close (keep filter)
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.12)),
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              constraints: const BoxConstraints(maxHeight: 380),
              decoration: BoxDecoration(
                color: p.cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: p.fieldBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: _resultsView(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultsView() {
    final p = context.palette;
    if (_searching) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            'No leads found',
            style: TextStyle(color: p.subtitle, fontSize: 13.5),
          ),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: _results.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: p.fieldBorder),
      itemBuilder: (context, i) {
        final l = _results[i];
        return InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            _closeOverlay(); // hide overlay…
            widget.onLeadTap?.call(l); // …then filter the My Leads list (the
            // committed term flows back via committedQuery → shows in the field)
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.leadNo.isEmpty ? '—' : l.leadNo,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.purple,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l.name.isEmpty ? '—' : l.name,
                        style: TextStyle(fontSize: 13.5, color: p.title),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: p.subtitle),
              ],
            ),
          ),
        );
      },
    );
  }
}
