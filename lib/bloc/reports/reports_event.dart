part of 'reports_bloc.dart';

abstract class ReportsEvent extends Equatable {
  const ReportsEvent();

  @override
  List<Object?> get props => [];
}

/// Load the monthly lead trend + yearly summary for [year].
class ReportsRequested extends ReportsEvent {
  const ReportsRequested({required this.year});
  final int year;

  @override
  List<Object?> get props => [year];
}
