import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/followups/followups_bloc.dart';
import '../../data/models/followup_item.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../../theme/app_colors.dart';
import '../widgets/dashboard_widgets.dart';
import 'lead_interaction_screen.dart';

/// Full "View All" follow-ups screen opened from Home → View All.
/// Two tabs (Call Rescheduled / Scheduled Visits), search by Lead ID or name,
/// and numbered server-side pagination. [initialTab]: 0 = calls, 1 = visits.
class FollowupsAllScreen extends StatelessWidget {
  const FollowupsAllScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  Widget build(BuildContext context) {
    final kind = initialTab == 1 ? FollowupKind.visit : FollowupKind.call;
    return BlocProvider(
      create: (_) => FollowupsBloc(repository: DashboardRepository())
        ..add(FollowupsTabChanged(kind)),
      child: const _FollowupsView(),
    );
  }
}

class _FollowupsView extends StatefulWidget {
  const _FollowupsView();

  @override
  State<_FollowupsView> createState() => _FollowupsViewState();
}

class _FollowupsViewState extends State<_FollowupsView> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    // Debounce so we re-hit the API once the user pauses typing — the result
    // always comes back on page 1 from the server.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      context.read<FollowupsBloc>().add(FollowupsSearchChanged(value));
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchCtrl.clear();
    context.read<FollowupsBloc>().add(const FollowupsSearchChanged(''));
    FocusScope.of(context).unfocus();
  }

  void _selectTab(FollowupKind kind) {
    final current = context.read<FollowupsBloc>().state.kind;
    if (current == kind) return;
    context.read<FollowupsBloc>().add(FollowupsTabChanged(kind));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.surface,
      appBar: AppBar(
        title: const Text('Today Task'),
        elevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: BlocBuilder<FollowupsBloc, FollowupsState>(
          builder: (context, state) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    children: [
                      _TabToggle(active: state.kind, onChanged: _selectTab),
                      const SizedBox(height: 12),
                      _searchField(),
                    ],
                  ),
                ),
                Expanded(child: _list(state)),
                if (state.status == FollowupsStatus.success &&
                    state.totalPages > 1)
                  _Pager(
                    current: state.pageNumber,
                    total: state.totalPages,
                    onTap: (pg) =>
                        context.read<FollowupsBloc>().add(
                              FollowupsPageRequested(pg),
                            ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _searchField() {
    final p = context.palette;
    return TextField(
      controller: _searchCtrl,
      onChanged: _onSearchChanged,
      textInputAction: TextInputAction.search,
      style: TextStyle(fontSize: 14, color: p.title),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Search by Lead ID or Lead Name',
        hintStyle: TextStyle(fontSize: 14, color: p.subtitle),
        prefixIcon: Icon(Icons.search, size: 20, color: p.subtitle),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _searchCtrl,
          builder: (context, value, _) => value.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  icon: Icon(Icons.close, size: 18, color: p.subtitle),
                  onPressed: _clearSearch,
                ),
        ),
        filled: true,
        fillColor: p.cardBg,
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.fieldBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.purple),
        ),
      ),
    );
  }

  Widget _list(FollowupsState state) {
    if (state.status == FollowupsStatus.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.status == FollowupsStatus.failure) {
      return _message(
        state.errorMessage ?? 'Failed to load follow-ups',
        showRetry: true,
      );
    }
    if (state.items.isEmpty) {
      return _message(
        state.kind == FollowupKind.call
            ? 'No rescheduled calls found'
            : 'No scheduled visits found',
      );
    }
    return RefreshIndicator(
      onRefresh: () async =>
          context.read<FollowupsBloc>().add(const FollowupsRefreshed()),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        itemCount: state.items.length,
        itemBuilder: (context, i) {
          final f = state.items[i];
          final isCall = state.kind == FollowupKind.call;
          return GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => LeadInteractionScreen(
                  lead: f.toLeadItem(),
                  initialKind: f.kind,
                ),
              ),
            ),
            child: TaskTile(
              leadId: f.leadNo.isEmpty ? '—' : f.leadNo,
              leadName: f.leadName.isEmpty ? '—' : f.leadName,
              rows: [
                if (f.mobile.isNotEmpty) ('Mobile Number:', f.mobile),
                (
                isCall ? 'Call Date & Time:' : 'Visit Date & Time:',
                f.dateTimeLabel,
                ),
                //if (f.remarks.isNotEmpty) ('Remarks:', f.remarks),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _message(String msg, {bool showRetry = false}) {
    final p = context.palette;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            msg,
            textAlign: TextAlign.center,
            style: TextStyle(color: p.subtitle, fontSize: 13.5),
          ),
          if (showRetry) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: () =>
                  context.read<FollowupsBloc>().add(const FollowupsRefreshed()),
              child: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }
}

// ---- Tab toggle (Call Rescheduled / Scheduled Visits) ----
class _TabToggle extends StatelessWidget {
  const _TabToggle({required this.active, required this.onChanged});
  final FollowupKind active;
  final ValueChanged<FollowupKind> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: p.cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.fieldBorder),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _seg(context, 'Call (Rescheduled)', FollowupKind.call),
          _seg(context, 'Scheduled Visits', FollowupKind.visit),
        ],
      ),
    );
  }

  Widget _seg(BuildContext context, String label, FollowupKind kind) {
    final selected = active == kind;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(kind),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
                    colors: [AppColors.purpleDeep, AppColors.purple],
                  )
                : null,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : context.palette.subtitle,
            ),
          ),
        ),
      ),
    );
  }
}

// ---- Numbered pagination row ----
class _Pager extends StatelessWidget {
  const _Pager({
    required this.current,
    required this.total,
    required this.onTap,
  });
  final int current;
  final int total;
  final ValueChanged<int> onTap;

  /// A small window of page numbers around the current page (with first/last
  /// always shown and ellipsis gaps), so a long list stays compact.
  List<int> _pages() {
    final set = <int>{1, total, current, current - 1, current + 1};
    final pages = set.where((p) => p >= 1 && p <= total).toList()..sort();
    return pages;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pages = _pages();
    final children = <Widget>[
      _arrow(context, Icons.chevron_left,
          enabled: current > 1, onTap: () => onTap(current - 1)),
    ];
    int? prev;
    for (final pg in pages) {
      if (prev != null && pg - prev > 1) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('…', style: TextStyle(color: p.subtitle)),
        ));
      }
      children.add(_num(context, pg));
      prev = pg;
    }
    children.add(_arrow(context, Icons.chevron_right,
        enabled: current < total, onTap: () => onTap(current + 1)));

    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.fieldBorder)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: children,
      ),
    );
  }

  Widget _num(BuildContext context, int pg) {
    final p = context.palette;
    final selected = pg == current;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: GestureDetector(
        onTap: selected ? null : () => onTap(pg),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
                    colors: [AppColors.purpleDeep, AppColors.purple],
                  )
                : null,
            color: selected ? null : p.cardBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? Colors.transparent : p.fieldBorder,
            ),
          ),
          child: Text(
            '$pg',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : p.title,
            ),
          ),
        ),
      ),
    );
  }

  Widget _arrow(BuildContext context, IconData icon,
      {required bool enabled, required VoidCallback onTap}) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: p.cardBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: p.fieldBorder),
          ),
          child: Icon(
            icon,
            size: 20,
            color: enabled ? p.title : p.subtitle.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }
}
