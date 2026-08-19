import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../bloc/leads/leads_bloc.dart';
import '../../data/models/lead_item.dart';
import '../../data/repositories/lead_repository.dart';
import '../../theme/app_colors.dart';
import '../widgets/lead_search_scaffold.dart';
import 'all_leads_screen.dart';
import 'lead_widgets.dart';

class MyLeadsTab extends StatelessWidget {
  const MyLeadsTab({super.key, this.onLeadTap});

  /// Tapping a lead from the shared search overlay (handled by DashboardShell).
  final ValueChanged<LeadItem>? onLeadTap;

  @override
  Widget build(BuildContext context) {
    // The LeadsBloc is provided by DashboardShell (so the search overlay can
    // drive this list); just consume it here.
    return _MyLeadsView(onLeadTap: onLeadTap);
  }
}

class _MyLeadsView extends StatefulWidget {
  const _MyLeadsView({this.onLeadTap});
  final ValueChanged<LeadItem>? onLeadTap;

  @override
  State<_MyLeadsView> createState() => _MyLeadsViewState();
}

class _MyLeadsViewState extends State<_MyLeadsView> {
  final _scroll = ScrollController();

  // Active status filter (null = All). Sent to /rm/list as `leadStatus` — the
  // list comes back filtered server-side.
  RmStatus? _activeFilter;

  // Status options from GET /rm/rm-status (loaded the first time the filter
  // dialog is opened).
  final LeadRepository _leadRepo = LeadRepository();
  List<RmStatus> _statuses = [];

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // Open the status filter — a centered, scrollable dialog (the list is long).
  // Loads the options from GET /rm/rm-status the first time.
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

    // Returns: 'ALL' for All Leads, an RmStatus for a status, null if dismissed.
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
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.7),
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
    if (selected == null) return; // dismissed → keep current
    final status = selected is RmStatus ? selected : null;
    setState(() => _activeFilter = status);
    // Reload from the server with the selected status (search kept).
    if (!mounted) return;
    final bloc = context.read<LeadsBloc>();
    bloc.add(LeadsRequested(
      search: bloc.state.search,
      leadStatus: status?.value ?? '',
    ));
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LeadsBloc, LeadsState>(
      builder: (context, state) {
        final p = context.palette;
        final Widget body;
        if (state.isLoading && state.items.isEmpty) {
          body = const Center(child: CircularProgressIndicator());
        } else if (state.status == LeadsStatus.failure && state.items.isEmpty) {
          body = LeadMessage(
            text: state.errorMessage ?? 'Failed to load leads',
            onRetry: () => context.read<LeadsBloc>().add(
                LeadsRequested(leadStatus: _activeFilter?.value ?? '')),
          );
        } else {
          final items = state.items; // already filtered server-side
          final title = _activeFilter?.displayName ?? 'All Leads';
          // Show how many are actually displayed (the tab caps at the first 10).
          final headerCount = items.length;
          body = RefreshIndicator(
            onRefresh: () async => context.read<LeadsBloc>().add(
              LeadsRequested(
                  search: state.search,
                  leadStatus: _activeFilter?.value ?? ''),
            ),
            child: ListView.builder(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              itemCount: items.length + 2, // title + footer
              itemBuilder: (context, index) {
                if (index == 0) {
                  // Header: title on the left, "View All" on the right (opens the
                  // full paginated list screen).
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            items.isNotEmpty ? '$title ($headerCount)' : title,
                            style: TextStyle(
                              fontSize: 16,
                              height: 19 / 16,
                              fontWeight: FontWeight.w700,
                              color: p.title,
                            ),
                          ),
                        ),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const AllLeadsScreen(),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'View All',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                              Icon(Icons.chevron_right,
                                  size: 18, color: AppColors.primary),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }
                if (index <= items.length) {
                  return LeadCard(lead: items[index - 1]);
                }
                // Footer: empty message or nothing (no infinite-scroll loader —
                // the tab only ever shows the first 10).
                if (items.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Center(
                      child: Text(
                        _activeFilter == null
                            ? 'No leads found'
                            : 'No leads in "${_activeFilter!.displayName}"',
                        style: TextStyle(color: p.subtitle, fontSize: 13.5),
                      ),
                    ),
                  );
                }
                return const SizedBox(height: 8);
              },
            ),
          );
        }
        return LeadSearchScaffold(
          showFilter: true,
          onFilter: _openFilterDialog,
          onLeadTap: widget.onLeadTap,
          committedQuery: state.search,
          onClearList: () => context.read<LeadsBloc>().add(
              LeadsRequested(leadStatus: _activeFilter?.value ?? '')),
          body: body,
        );
      },
    );
  }
}
