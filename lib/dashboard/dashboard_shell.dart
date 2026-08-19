import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/leads/leads_bloc.dart';
import '../core/constants/app_assets.dart';
import '../core/device/app_device.dart';
import '../core/widgets/app_icon.dart';
import '../data/models/lead_item.dart';
import '../data/repositories/lead_repository.dart';
import '../routes/app_routes.dart';
import '../theme/app_colors.dart';
import 'screens/home_tab.dart';
import 'screens/my_leads_tab.dart';
import 'screens/reports_tab.dart';
import 'screens/more_tab.dart';

/// Root of the post-login app: four tabs behind a custom bottom nav bar.
class DashboardShell extends StatefulWidget {
  const DashboardShell({super.key, this.initialIndex = 0});
  final int initialIndex;

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> with RouteAware {
  late int _index = widget.initialIndex;

  // Bumped every time the user returns to the dashboard from a pushed page.
  // It re-keys the whole bloc subtree so Home / My Leads / Reports all reload.
  int _refreshTick = 0;

  static const _tabs = [
    _NavItem('Home', AppAssets.navHome),
    _NavItem('My Leads', AppAssets.navMyLeads),
    _NavItem('Reports', AppAssets.navReports),
    _NavItem('More', AppAssets.navMore),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  // A page pushed on top of the dashboard was popped → we're visible again.
  // Refresh every tab (Home stat-cards + follow-ups, My Leads, Reports).
  @override
  void didPopNext() {
    if (mounted) setState(() => _refreshTick++);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // One LeadsBloc for the whole shell (so a lead tapped from the Home/My Leads
    // search overlay refreshes the My Leads list + switches tab). Using create:
    // lets flutter_bloc close it SAFELY on teardown (e.g. logout) after the
    // children deactivate — manually closing a .value provider triggered a
    // "_dependents.isEmpty" assertion.
    return BlocProvider(
      // Re-keyed on every return to the dashboard so the LeadsBloc and the
      // tab subtree (HomeTab's DashboardBloc, ReportsTab's ReportsBloc) are
      // recreated → each reloads its data. `create:` closes the old blocs
      // safely on teardown.
      key: ValueKey('dashboard-$_refreshTick'),
      create: (_) =>
          LeadsBloc(repository: LeadRepository())..add(const LeadsRequested()),
      child: Builder(
        builder: (context) {
          // Search result tapped → filter the My Leads list + switch to it.
          void openLeadInList(LeadItem lead) {
            final term = lead.leadNo.isNotEmpty ? lead.leadNo : lead.name;
            context.read<LeadsBloc>().add(LeadsRequested(search: term));
            setState(() => _index = 1);
          }

          return Scaffold(
            body: IndexedStack(
              index: _index,
              children: [
                HomeTab(onLeadTap: openLeadInList),
                MyLeadsTab(onLeadTap: openLeadInList),
                const ReportsTab(),
                const MoreTab(),
              ],
            ),
            bottomNavigationBar: Container(
              decoration: BoxDecoration(
                color: p.surface,
                border: Border(top: BorderSide(color: p.fieldBorder)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.only(
                    top: 6,
                    bottom: 4 + AppDevice.bottomNavGap,
                  ),
                  child: Row(
                    children: [
                      for (int i = 0; i < _tabs.length; i++)
                        Expanded(
                          child: _NavButton(
                            item: _tabs[i],
                            active: _index == i,
                            onTap: () => setState(() => _index = i),
                            inactiveColor: p.iconGrey,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.label, this.icon);
  final String label;
  final String icon;
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.active,
    required this.onTap,
    required this.inactiveColor,
  });
  final _NavItem item;
  final bool active;
  final VoidCallback onTap;
  final Color inactiveColor;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.purple : inactiveColor;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(item.icon, size: 20, color: color),
            const SizedBox(height: 3),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                color: color,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
