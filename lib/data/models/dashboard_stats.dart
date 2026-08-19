import 'package:equatable/equatable.dart';

/// Home stat-card counts from `GET /rm/dashboard` (the single object in `data[0]`).
class DashboardStats extends Equatable {
  const DashboardStats({
    this.totalLeads = 0,
    this.convertedLeads = 0,
    this.rejectedLeads = 0,
    this.conversionRate = 0,
  });

  final int totalLeads;
  final int convertedLeads;
  final int rejectedLeads;
  final num conversionRate;

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    int i(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    num n(dynamic v) {
      if (v is num) return v;
      if (v is String) return num.tryParse(v) ?? 0;
      return 0;
    }

    return DashboardStats(
      totalLeads: i(json['totalLeads']),
      convertedLeads: i(json['convertedLeads']),
      rejectedLeads: i(json['rejectedLeads']),
      conversionRate: n(json['conversionRate']),
    );
  }

  /// Current API: `data[]` is a list of `{name, count}` rows. Match each row to
  /// its stat by name. (Falls back to [fromJson] for the legacy single-object
  /// shape with explicit keys.)
  factory DashboardStats.fromItems(List items) {
    if (items.length == 1 &&
        items.first is Map &&
        (items.first as Map).containsKey('totalLeads')) {
      return DashboardStats.fromJson(
          Map<String, dynamic>.from(items.first as Map));
    }

    // Raw `count` for a row (num handles decimals like "40.74"; null if absent).
    num? rawCountFor(String label) {
      for (final e in items) {
        if (e is Map) {
          final name = (e['name']?.toString() ?? '').trim().toLowerCase();
          if (name == label.toLowerCase()) {
            final c = e['count'];
            if (c is num) return c;
            if (c is String) return num.tryParse(c);
          }
        }
      }
      return null;
    }

    int countFor(String label) => (rawCountFor(label) ?? 0).toInt();

    return DashboardStats(
      totalLeads: countFor('Total Leads'),
      convertedLeads: countFor('Converted Leads'),
      rejectedLeads: countFor('Rejected Leads'),
      // Conversion Rate is a decimal (e.g. "40.74") — keep it as a num.
      conversionRate: rawCountFor('Conversion Rate') ?? 0,
    );
  }

  /// "90%" — drops a trailing `.0` (90.0 -> "90%", 12.5 -> "12.5%").
  String get conversionRateLabel {
    final r = conversionRate;
    final s = (r % 1 == 0) ? r.toInt().toString() : r.toString();
    return '$s%';
  }

  @override
  List<Object?> get props =>
      [totalLeads, convertedLeads, rejectedLeads, conversionRate];
}
