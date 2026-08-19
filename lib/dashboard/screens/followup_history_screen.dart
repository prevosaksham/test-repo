import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/network/api_exception.dart';
import '../../data/models/followup_item.dart';
import '../../data/models/followup_page.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../../theme/app_colors.dart';
import '../widgets/dashboard_widgets.dart';
import 'lead_interaction_screen.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "Followup History" screen — opened from Home → Today Task → View All.
/// Server-paginated (`POST /followup/history`) with search (Lead ID / name) and
/// a date filter. 10 rows per page; tap a page number to load that page.
class FollowupHistoryScreen extends StatefulWidget {
  const FollowupHistoryScreen({super.key});

  @override
  State<FollowupHistoryScreen> createState() => _FollowupHistoryScreenState();
}

class _FollowupHistoryScreenState extends State<FollowupHistoryScreen> {
  final DashboardRepository _repo = DashboardRepository();
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  String _search = '';
  DateTime? _date; // selected date filter (null = all)
  FollowupKind _kind = FollowupKind.call; // 0 = calls, 1 = visits
  int _page = 1;
  bool _loading = true;
  String? _error;
  FollowupPage _data = FollowupPage.empty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  String get _dateParam => _date == null
      ? ''
      : '${_date!.year.toString().padLeft(4, '0')}-'
          '${_date!.month.toString().padLeft(2, '0')}-'
          '${_date!.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _repo.getFollowupHistory(
        page: _page,
        search: _search,
        date: _dateParam,
        followupType: _kind == FollowupKind.call ? 'CALL' : 'VISIT',
      );
      if (!mounted) return;
      setState(() {
        _data = page;
        _page = page.pageNumber;
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
        _error = 'Something went wrong. Please try again.';
        _loading = false;
      });
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _search = value;
      _page = 1; // a new search resets to the first page
      _load();
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchCtrl.clear();
    _search = '';
    _page = 1;
    FocusScope.of(context).unfocus();
    _load();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
    );
    if (picked == null) return;
    setState(() {
      _date = picked;
      _page = 1;
    });
    _load();
  }

  void _clearDate() {
    setState(() {
      _date = null;
      _page = 1;
    });
    _load();
  }

  // Reset everything — clear search + date and reload page 1.
  void _resetAll() {
    _debounce?.cancel();
    _searchCtrl.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _search = '';
      _date = null;
      _page = 1;
    });
    _load();
  }

  void _goToPage(int pg) {
    if (pg == _page) return;
    setState(() => _page = pg);
    _load();
  }

  void _selectTab(FollowupKind kind) {
    if (_kind == kind) return;
    setState(() {
      _kind = kind;
      _page = 1; // switching tabs starts from the first page
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.surface,
      appBar: AppBar(
        backgroundColor: p.cardBg, // white action bar (theme card colour)
        foregroundColor: p.title,
        elevation: 0,
        title: const Text('Follow-Ups', style: TextStyle(fontSize: 17)),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                children: [
                  _TabToggle(active: _kind, onChanged: _selectTab),
                  const SizedBox(height: 10),
                  _searchField(),
                  const SizedBox(height: 10),
                  _dateFilter(),
                ],
              ),
            ),
            Expanded(child: _list()),
            if (!_loading &&
                _error == null &&
                _data.totalPages > 1 &&
                _data.items.isNotEmpty)
              _Pager(
                current: _data.pageNumber,
                total: _data.totalPages,
                onTap: _goToPage,
              ),
          ],
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

  Widget _dateFilter() {
    final p = context.palette;
    final label = _date == null
        ? 'Filter by date'
        : '${_date!.day.toString().padLeft(2, '0')} '
            '${_months[_date!.month - 1]} ${_date!.year}';
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: _pickDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: p.cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.fieldBorder),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today_outlined,
                      size: 18, color: p.subtitle),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        color: _date == null ? p.subtitle : p.title,
                        fontWeight:
                            _date == null ? FontWeight.w400 : FontWeight.w600,
                      ),
                    ),
                  ),
                  if (_date != null)
                    GestureDetector(
                      onTap: _clearDate,
                      behavior: HitTestBehavior.opaque,
                      child: Icon(Icons.close, size: 18, color: p.subtitle),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Reset — clears search + date and reloads from page 1.
        GestureDetector(
          onTap: _resetAll,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: AppColors.buttonGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.refresh, size: 18, color: Colors.white),
                SizedBox(width: 6),
                Text(
                  'Reset',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _list() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _message(_error!, showRetry: true);
    }
    // Safety net: show only the selected tab's kind even if the API returns
    // mixed rows (in case it doesn't filter on followupType server-side).
    final items = _data.items.where((f) => f.kind == _kind).toList();
    if (items.isEmpty) {
      return _message(
        _kind == FollowupKind.call
            ? 'No rescheduled calls found'
            : 'No scheduled visits found',
      );
    }
    final isCall = _kind == FollowupKind.call;
    return RefreshIndicator(
      onRefresh: () async => _load(),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final f = items[i];
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
              // Value aligns under "Lead Name" (label under "Lead ID").
              alignValueToName: true,
              leadId: f.leadNo.isEmpty ? '—' : f.leadNo,
              leadName: f.leadName.isEmpty ? '—' : f.leadName,
              rows: [
                if (f.mobile.isNotEmpty) ('Mobile Number:', f.mobile),
                (
                  isCall ? 'Call Date & Time:' : 'Visit Date & Time:',
                  f.dateTimeLabel,
                ),
                // Dealer + Remarks only on VISIT rows (hidden for calls).
                if (!isCall && f.dealerName.isNotEmpty) ('Dealer:', f.dealerName),
                //if (!isCall && f.remarks.isNotEmpty) ('Remarks:', f.remarks),
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
            TextButton(onPressed: _load, child: const Text('Retry')),
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

// ---- Numbered pagination row (all page numbers, left-aligned, scrollable) ----
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
    final children = <Widget>[
      _arrow(context, Icons.chevron_left,
          enabled: current > 1, onTap: () => onTap(current - 1)),
      for (var pg = 1; pg <= total; pg++) _num(context, pg),
      _arrow(context, Icons.chevron_right,
          enabled: current < total, onTap: () => onTap(current + 1)),
    ];
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.fieldBorder)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: children,
        ),
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
