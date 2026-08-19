part of 'reports_bloc.dart';

enum ReportsStatus { initial, loading, success, failure }

class ReportsState extends Equatable {
  const ReportsState({
    this.status = ReportsStatus.initial,
    this.trend = const LeadTrend(),
    this.year = 2026,
    this.errorMessage,
  });

  final ReportsStatus status;
  final LeadTrend trend;
  final int year;
  final String? errorMessage;

  bool get isLoading => status == ReportsStatus.loading;

  ReportsState copyWith({
    ReportsStatus? status,
    LeadTrend? trend,
    int? year,
    String? errorMessage,
  }) {
    return ReportsState(
      status: status ?? this.status,
      trend: trend ?? this.trend,
      year: year ?? this.year,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, trend, year, errorMessage];
}
