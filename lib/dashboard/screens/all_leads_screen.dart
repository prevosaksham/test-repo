import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../bloc/leads/leads_bloc.dart';
import '../../data/models/lead_item.dart';
import '../../data/repositories/lead_repository.dart';
import '../../theme/app_colors.dart';
import '../widgets/lead_search_scaffold.dart';
import 'lead_widgets.dart';

/// Full "View All" leads screen (opened from the My Leads tab header).
/// Same top + search as the My Leads tab, with numbered server-side pagination
/// — 10 leads per page, tap a page number to load that page.
class AllLeadsScreen extends StatelessWidget {
  const AllLeadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LeadsBloc(repository: LeadRepository())
        ..add(const LeadsPageSelected(1)),
      child: const _AllLeadsView(),
    );
  }
}

class _AllLeadsView extends StatefulWidget {
  const _AllLeadsView();

  @override
  State<_AllLeadsView> createState() => _AllLeadsViewState();
}

class _AllLeadsViewState extends State<_AllLeadsView> {
  final LeadRepository _leadRepo = LeadRepository();
  RmStatus? _activeFilter; // null = All; sent to /rm/list as leadStatus.
  List<RmStatus> _statuses = [];

  Future<void> _openFilterDialog() async {
    if (_statuses.isEmpty) {
      try {
        final list = await _leadRepo.getRmStatuses();
        if (mounted) _statuses = list;
      } catch (_) {
        // ignore — dialog still opens with just "All Leads"
      }
    }
    if (!mounted) return;
    final selected = await showDialog<Object?>(
      context: context,
      builder: (ctx) {
        final p = ctx.palette;
        return Dialog(
          backgroundColor: p.cardBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: ConstrainedBox(
            constraints:
                BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Filter by Status',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: p.title)),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        behavior: HitTestBehavior.opaque,
                        child: Icon(Icons.close, size: 20, color: p.subtitle),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: p.fieldBorder),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    children: [
                      LeadFilterRow(
                        label: 'All Leads',
                        selected: _activeFilter == null,
                        onTap: () => Navigator.pop(ctx, 'ALL'),
                      ),
                      for (final s in _statuses)
                        LeadFilterRow(
                          label: s.displayName,
                          selected: _activeFilter?.value == s.value,
                          onTap: () => Navigator.pop(ctx, s),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected == null) return;
    final status = selected is RmStatus ? selected : null;
    setState(() => _activeFilter = status);
    // Reload page 1 from the server with the selected status (search kept).
    if (!mounted) return;
    final bloc = context.read<LeadsBloc>();
    bloc.add(LeadsPageSelected(1,
        search: bloc.state.search, leadStatus: status?.value ?? ''));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.surface,
      // Same top as the My Leads tab — the orange DashboardHeader (avatar +
      // welcome name + notification + search + filter), no separate AppBar.
      body: BlocBuilder<LeadsBloc, LeadsState>(
        builder: (context, state) {
          final bloc = context.read<LeadsBloc>();
          final items = state.items; // already filtered server-side
          return LeadSearchScaffold(
            showProfile: false, // no Welcome/profile/name…
            title: 'All Leads', // …show the page title instead
            onBack: () => Navigator.of(context).maybePop(),
            showFilter: true, // search + notification + filter
            onFilter: _openFilterDialog,
            // Picking a search result (Lead ID / name) filters THIS screen's
            // list — its own bloc, not the dashboard's My Leads bloc sitting
            // behind this route.
            onLeadTap: (lead) => bloc.add(LeadsPageSelected(
              1,
              search: lead.leadNo.isNotEmpty ? lead.leadNo : lead.name,
              leadStatus: _activeFilter?.value ?? '',
            )),
            committedQuery: state.search,
            onClearList: () => bloc.add(LeadsPageSelected(1,
                leadStatus: _activeFilter?.value ?? '')),
            body: Column(
              children: [
                Expanded(child: _listArea(context, state, items)),
                // Numbered pagination — stays visible during page loads.
                if (state.totalPages > 1 && state.items.isNotEmpty)
                  _Pager(
                    current: state.pageNumber,
                    total: state.totalPages,
                    onTap: (pg) => bloc.add(LeadsPageSelected(pg,
                        search: state.search,
                        leadStatus: _activeFilter?.value ?? '')),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _listArea(
      BuildContext context, LeadsState state, List<LeadItem> items) {
    final p = context.palette;
    if (state.isLoading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.status == LeadsStatus.failure && state.items.isEmpty) {
      return LeadMessage(
        text: state.errorMessage ?? 'Failed to load leads',
        onRetry: () => context.read<LeadsBloc>().add(
            LeadsPageSelected(1, leadStatus: _activeFilter?.value ?? '')),
      );
    }
    if (items.isEmpty) {
      return Center(
        child: Text(
          _activeFilter == null
              ? 'No leads found'
              : 'No leads in "${_activeFilter!.displayName}"',
          textAlign: TextAlign.center,
          style: TextStyle(color: p.subtitle, fontSize: 13.5),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () async => context.read<LeadsBloc>().add(LeadsPageSelected(
          state.pageNumber,
          search: state.search,
          leadStatus: _activeFilter?.value ?? '')),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        itemCount: items.length,
        itemBuilder: (context, i) => LeadCard(lead: items[i]),
      ),
    );
  }
}

// ---- Numbered pagination row (page circles + prev/next) ----
class _Pager extends StatelessWidget {
  const _Pager({
    required this.current,
    required this.total,
    required this.onTap,
  });
  final int current;
  final int total;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // Prev arrow fixed at the start, next arrow fixed at the end; only the page
    // numbers (1..total) scroll horizontally in between.
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.fieldBorder)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      child: Row(
        children: [
          _arrow(context, Icons.chevron_left,
              enabled: current > 1, onTap: () => onTap(current - 1)),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  for (var pg = 1; pg <= total; pg++) _num(context, pg),
                ],
              ),
            ),
          ),
          _arrow(context, Icons.chevron_right,
              enabled: current < total, onTap: () => onTap(current + 1)),
        ],
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
            gradient: selected ? AppColors.buttonGradient : null,
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
