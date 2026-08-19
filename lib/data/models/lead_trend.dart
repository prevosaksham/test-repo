import 'package:equatable/equatable.dart';

int _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

/// One month of the trend chart (`data.monthlyLeadTrend[]`).
class MonthlyTrendPoint extends Equatable {
  const MonthlyTrendPoint({
    required this.month,
    required this.newCount,
    required this.approved,
    required this.inProgress,
  });

  final String month;
  final int newCount;
  final int approved;
  final int inProgress;

  int get total => newCount + approved + inProgress;

  factory MonthlyTrendPoint.fromJson(Map<String, dynamic> json) {
    return MonthlyTrendPoint(
      month: json['month']?.toString() ?? '',
      newCount: _asInt(json['new']),
      approved: _asInt(json['approved']),
      inProgress: _asInt(json['inProgress']),
    );
  }

  @override
  List<Object?> get props => [month, newCount, approved, inProgress];
}

/// One Application-Status row (`data.yearlySummary[]`).
class YearlySummaryItem extends Equatable {
  const YearlySummaryItem({required this.name, required this.count});

  final String name;
  final int count;

  /// "In_Progress" -> "In Progress".
  String get label {
    final clean = name.replaceAll('_', ' ').trim();
    if (clean.isEmpty) return clean;
    return clean
        .split(' ')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  factory YearlySummaryItem.fromJson(Map<String, dynamic> json) {
    return YearlySummaryItem(
      name: json['name']?.toString() ?? '',
      count: _asInt(json['count']),
    );
  }

  @override
  List<Object?> get props => [name, count];
}

/// Full payload of `POST /rm/getMonthlyLeadTrend` (`data.{monthlyLeadTrend,
/// yearlySummary}`).
class LeadTrend extends Equatable {
  const LeadTrend({this.monthly = const [], this.summary = const []});

  final List<MonthlyTrendPoint> monthly;
  final List<YearlySummaryItem> summary;

  factory LeadTrend.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    final m = data is Map ? data['monthlyLeadTrend'] : null;
    final y = data is Map ? data['yearlySummary'] : null;
    return LeadTrend(
      monthly: (m is List)
          ? m
              .whereType<Map>()
              .map((e) => MonthlyTrendPoint.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      summary: (y is List)
          ? y
              .whereType<Map>()
              .map((e) => YearlySummaryItem.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }

  @override
  List<Object?> get props => [monthly, summary];
}
