import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../bloc/dashboard/dashboard_bloc.dart';
import '../../core/constants/app_assets.dart';
import '../../core/widgets/app_icon.dart';
import '../../data/models/followup_item.dart';
import '../../data/models/lead_item.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../../theme/app_colors.dart';
import '../models/dashboard_data.dart';
import '../widgets/dashboard_widgets.dart';
import '../widgets/lead_search_scaffold.dart';
import 'followup_history_screen.dart';
import 'lead_interaction_screen.dart';

/// Open the lead's interaction screen from a follow-up card, landing on the
/// step that matches the follow-up type (CALL → Call, VISIT → Visit).
void _openFollowupLead(BuildContext context, FollowupItem item) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => LeadInteractionScreen(
        lead: item.toLeadItem(),
        initialKind: item.kind,
      ),
    ),
  );
}

class HomeTab extends StatelessWidget {
  const HomeTab({super.key, this.onLeadTap});

  /// Tapping a lead from the search overlay (handled by DashboardShell).
  final ValueChanged<LeadItem>? onLeadTap;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          DashboardBloc(repository: DashboardRepository())
            ..add(const DashboardLoadRequested()),
      child: _HomeView(onLeadTap: onLeadTap),
    );
  }
}

class _HomeView extends StatefulWidget {
  const _HomeView({this.onLeadTap});
  final ValueChanged<LeadItem>? onLeadTap;

  @override
  State<_HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<_HomeView> {
  int _tab = 0; // 0 = calls, 1 = visits

  @override
  Widget build(BuildContext context) {
    return LeadSearchScaffold(
      onLeadTap: widget.onLeadTap,
      body: RefreshIndicator(
        onRefresh: () async =>
            context.read<DashboardBloc>().add(const DashboardLoadRequested()),
        child: BlocBuilder<DashboardBloc, DashboardState>(
          builder: (context, state) {
            final p = context.palette;
            return ListView(
              // No title on Home, so less top gap than the titled tabs.
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
              children: [
                // 2×2 stat grid (API counts).
                _statsGrid(state),
                const SizedBox(height: 16),
                // Today Task.
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Heading + "View All" (opens the Followup History
                      // screen — search + date filter + pagination).
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              "Pending Task",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: p.title,
                              ),
                            ),
                          ),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const FollowupHistoryScreen(),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'View All',
                                  style: TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                                Icon(Icons.chevron_right,
                                    size: 18, color: AppColors.primary),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _TaskToggle(
                        index: _tab,
                        onChanged: (i) => setState(() => _tab = i),
                      ),
                      const SizedBox(height: 14),
                      _taskList(state),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ---- stat cards from the /rm/dashboard counts ----
  Widget _statsGrid(DashboardState state) {
    final s = state.stats;
    final loading = state.isLoading;
    String v(int n) => loading ? '—' : n.toString();
    final cards = <StatCard>[
      StatCard(
        icon: AppAssets.totalLeads,
        value: v(s.totalLeads),
        label: 'Total Leads',
      ),
      StatCard(
        icon: AppAssets.convertedLeads,
        value: v(s.convertedLeads),
        label: 'Converted Leads',
      ),
      StatCard(
        icon: AppAssets.rejectedLeads,
        value: v(s.rejectedLeads),
        label: 'Rejected Leads',
      ),
      StatCard(
        icon: AppAssets.conversionRate,
        value: loading ? '—' : s.conversionRateLabel,
        label: 'Conversion Rate',
      ),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.28,
      children: [for (final c in cards) _StatTile(stat: c)],
    );
  }

  // ---- Today Task list from the /followup/list data, split by tab ----
  Widget _taskList(DashboardState state) {
    if (state.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (state.status == DashboardStatus.failure) {
      return _placeholder(state.errorMessage ?? 'Failed to load tasks');
    }
    final items = _tab == 0 ? state.calls : state.visits;
    if (items.isEmpty) {
      return _placeholder(
        _tab == 0 ? 'No rescheduled calls' : 'No scheduled visits',
      );
    }
    // Home shows at most 2 per tab; the rest live behind "View All".
    return Column(
      children: [
        for (final f in items.take(2))
          if (_tab == 0) _CallCard(item: f) else _VisitCard(item: f),
      ],
    );
  }

  Widget _placeholder(String msg) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Text(
          msg,
          textAlign: TextAlign.center,
          style: TextStyle(color: p.subtitle, fontSize: 13.5),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.stat});
  final StatCard stat;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: p.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.fieldBorder),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: p.fieldBorder),
            ),
            child: AppIcon(stat.icon, size: 19, color: AppColors.purple),
          ),
          const SizedBox(height: 5),
          Text(
            stat.value,
            maxLines: 1,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: p.title,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            stat.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13.5, color: p.subtitle),
          ),
        ],
      ),
    );
  }
}

class _TaskToggle extends StatelessWidget {
  const _TaskToggle({required this.index, required this.onChanged});
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.fieldBorder),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [_seg('Call (Rescheduled)', 0), _seg('Scheduled Visits', 1)],
      ),
    );
  }

  Widget _seg(String label, int i) {
    final active = index == i;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(i),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: active
                ? const LinearGradient(
                    colors: [AppColors.purpleDeep, AppColors.purple],
                  )
                : null,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Builder(
            builder: (context) {
              return Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.white : context.palette.subtitle,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CallCard extends StatelessWidget {
  const _CallCard({required this.item});
  final FollowupItem item;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openFollowupLead(context, item),
      child: TaskTile(
        leadId: item.leadNo.isEmpty ? '—' : item.leadNo,
        leadName: item.leadName.isEmpty ? '—' : item.leadName,
        rows: [
          if (item.mobile.isNotEmpty) ('Mobile Number:', item.mobile),
          ('Call Date & Time:', item.dateTimeLabel),
          if (item.dealerName.isNotEmpty) ('Dealer:', item.dealerName),
          // if (item.remarks.isNotEmpty) ('Remarks:', item.remarks),
        ],
      ),
    );
  }
}

class _VisitCard extends StatelessWidget {
  const _VisitCard({required this.item});
  final FollowupItem item;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openFollowupLead(context, item),
      child: TaskTile(
        leadId: item.leadNo.isEmpty ? '—' : item.leadNo,
        leadName: item.leadName.isEmpty ? '—' : item.leadName,
        rows: [
          if (item.mobile.isNotEmpty) ('Mobile Number:', item.mobile),
          ('Visit Date & Time:', item.dateTimeLabel),
          if (item.dealerName.isNotEmpty) ('Dealer:', item.dealerName),
          // if (item.remarks.isNotEmpty) ('Remarks:', item.remarks),
        ],
      ),
    );
  }
}
