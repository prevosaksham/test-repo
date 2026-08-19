import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../bloc/reports/reports_bloc.dart';
import '../../data/models/lead_trend.dart';
import '../../data/repositories/report_repository.dart';
import '../../theme/app_colors.dart';
import '../widgets/dashboard_widgets.dart';
import '../widgets/dashboard_header.dart';

class ReportsTab extends StatelessWidget {
  const ReportsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          ReportsBloc(repository: ReportRepository())
            ..add(ReportsRequested(year: DateTime.now().year)),
      child: const _ReportsView(),
    );
  }
}

class _ReportsView extends StatelessWidget {
  const _ReportsView();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const DashboardHeader(),
        Expanded(
          child: BlocBuilder<ReportsBloc, ReportsState>(
            builder: (context, state) {
              final p = context.palette;
              final monthly = state.trend.monthly;
              final summary = state.trend.summary;
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                children: [
                  Text(
                    'Reports',
                    style: TextStyle(
                      fontSize: 16,
                      height: 19 / 16,
                      fontWeight: FontWeight.w700,
                      color: p.title,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Monthly Lead Trend',
                              style: TextStyle(
                                fontSize: 16,
                                height: 19 / 16,
                                fontWeight: FontWeight.w700,
                                color: p.title,
                              ),
                            ),
                            _YearDropdown(
                              year: state.year,
                              onChanged: (y) => context.read<ReportsBloc>().add(
                                ReportsRequested(year: y),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _chartArea(context, state, monthly),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Application Status',
                          style: TextStyle(
                            fontSize: 16,
                            height: 19 / 16,
                            fontWeight: FontWeight.w700,
                            color: p.title,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _funnelArea(context, state, summary),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _chartArea(
    BuildContext context,
    ReportsState state,
    List<MonthlyTrendPoint> data,
  ) {
    if (state.isLoading && data.isEmpty) return const _Loader();
    if (state.status == ReportsStatus.failure && data.isEmpty) {
      return _Empty(state.errorMessage ?? 'Failed to load');
    }
    if (data.isEmpty) return const _Empty('No data for this year');
    return Column(
      children: [
        _TrendChart(data: data),
        const SizedBox(height: 14),
        const _Legend(),
      ],
    );
  }

  Widget _funnelArea(
    BuildContext context,
    ReportsState state,
    List<YearlySummaryItem> items,
  ) {
    if (state.isLoading && items.isEmpty) return const _Loader();
    if (state.status == ReportsStatus.failure && items.isEmpty) {
      return _Empty(state.errorMessage ?? 'Failed to load');
    }
    if (items.isEmpty) return const _Empty('No data for this year');
    return _Funnel(items: items);
  }
}

class _Loader extends StatelessWidget {
  const _Loader();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 28),
    child: Center(child: CircularProgressIndicator()),
  );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: context.palette.subtitle, fontSize: 13.5),
      ),
    ),
  );
}

class _YearDropdown extends StatelessWidget {
  const _YearDropdown({required this.year, required this.onChanged});
  final int year;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // Always the last 3 years ending at the current year (e.g. 2026 -> [2026,
    // 2025, 2024]); rolls forward automatically each new year, no manual edits.
    final currentYear = DateTime.now().year;
    final years = [currentYear, currentYear - 1, currentYear - 2];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.fieldBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: years.contains(year) ? year : currentYear,
          isDense: true,
          icon: Icon(Icons.keyboard_arrow_down, color: p.subtitle),
          style: TextStyle(
            fontSize: 14,
            color: p.title,
            fontWeight: FontWeight.w600,
          ),
          dropdownColor: p.surface,
          items: years
              .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
              .toList(),
          onChanged: (y) => y == null ? null : onChanged(y),
        ),
      ),
    );
  }
}

/// Stacked horizontal bars per month with a Y axis (Months) on the left and an
/// X axis (Leads) at the bottom with a 0..max scale — matches the Figma. Bars
/// scale against a fixed axis max (rounded to 10s, min 50), segment counts shown
/// inside.
class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.data});
  final List<MonthlyTrendPoint> data;

  static const _monthsLabelW = 16.0; // rotated "Months"
  static const _monthW = 34.0; // "Jun" etc.
  static const _gap1 = 4.0;
  static const _gap2 = 8.0;
  static const _rowH = 34.0;
  static const _barH = 26.0;

  double get _leftInset => _monthsLabelW + _gap1 + _monthW + _gap2;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    final maxTotal = data.isEmpty
        ? 0
        : data.map((m) => m.total).reduce((a, b) => a > b ? a : b);
    // X scale: round up to the next 10, never below 50 (like the design).
    var axisMax = ((maxTotal + 9) ~/ 10) * 10;
    if (axisMax < 50) axisMax = 50;
    final ticks = [for (var t = 0; t <= axisMax; t += 10) t];
    final axisColor = p.fieldBorder;

    return Column(
      children: [
        SizedBox(
          height: data.length * _rowH,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // rotated "Months" axis title
              SizedBox(
                width: _monthsLabelW,
                child: Center(
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: Text(
                      'Months',
                      style: TextStyle(fontSize: 12, color: p.subtitle),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: _gap1),
              // month labels, aligned to each bar row
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final m in data)
                    SizedBox(
                      width: _monthW,
                      height: _rowH,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          m.month,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: p.title,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: _gap2),
              // plot area with Y axis (left) + X axis (bottom)
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(left: BorderSide(color: axisColor)),
                  ),
                  child: LayoutBuilder(
                    builder: (context, c) {
                      const padL = 6.0;
                      final plotW = c.maxWidth - padL;
                      return Padding(
                        padding: const EdgeInsets.only(left: padL),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final m in data)
                              SizedBox(
                                height: _rowH,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: SizedBox(
                                    width:
                                        plotW *
                                        (m.total / axisMax).clamp(0.0, 1.0),
                                    height: _barH,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.zero,
                                      child: Row(
                                        children: [
                                          _seg(m.newCount, AppColors.chartNew),
                                          _seg(
                                            m.approved,
                                            AppColors.chartApproved,
                                          ),
                                          _seg(
                                            m.inProgress,
                                            AppColors.chartProgress,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        // X axis line (drawn separately so it never steals height from the bars)
        Padding(
          padding: EdgeInsets.only(left: _leftInset),
          child: Container(height: 1, color: axisColor),
        ),
        // X axis tick labels (0..axisMax), aligned under the plot
        Padding(
          padding: EdgeInsets.only(left: _leftInset, top: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final t in ticks)
                Text('$t', style: TextStyle(fontSize: 11, color: p.subtitle)),
            ],
          ),
        ),
        const SizedBox(height: 2),
        // X axis title
        Padding(
          padding: EdgeInsets.only(left: _leftInset),
          child: Center(
            child: Text(
              'Leads',
              style: TextStyle(fontSize: 12, color: p.subtitle),
            ),
          ),
        ),
      ],
    );
  }

  // A segment only renders when it has a value (0 -> nothing); its count is
  // shown INSIDE the coloured block.
  Widget _seg(int value, Color color) {
    if (value <= 0) return const SizedBox.shrink();
    return Expanded(
      flex: value,
      child: Container(
        color: color,
        alignment: Alignment.center,
        child: Text(
          '$value',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 18,
      runSpacing: 8,
      children: const [
        _LegendDot(AppColors.chartNew, 'New'),
        _LegendDot(AppColors.chartApproved, 'Approved'),
        _LegendDot(AppColors.chartProgress, 'In progress'),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot(this.color, this.label);
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(fontSize: 13, color: context.palette.subtitle),
        ),
      ],
    );
  }
}

/// Stacked funnel from the yearly summary: centered bars, width scales with the
/// count. Colours cycle a fixed palette (the API doesn't send a colour here).
class _Funnel extends StatelessWidget {
  const _Funnel({required this.items});
  final List<YearlySummaryItem> items;

  static const _palette = [
    AppColors.purple,
    AppColors.statusRed,
    AppColors.chartProgress,
    AppColors.statusBlue,
    AppColors.chartApproved,
    AppColors.chartNew,
    AppColors.purpleDeep,
  ];

  @override
  Widget build(BuildContext context) {
    var maxV = items
        .map((s) => s.count)
        .reduce((a, b) => a > b ? a : b)
        .toDouble();
    if (maxV <= 0) maxV = 1;

    return LayoutBuilder(
      builder: (context, c) {
        final maxW = c.maxWidth;
        const minW = 0.42; // smallest bar still readable (fraction of width)
        return Column(
          children: [
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  width: maxW * (minW + (1 - minW) * (items[i].count / maxV)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: _palette[i % _palette.length],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '${items[i].count}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        items[i].label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
