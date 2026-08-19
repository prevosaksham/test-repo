part of 'dashboard_bloc.dart';

abstract class DashboardEvent extends Equatable {
  const DashboardEvent();

  @override
  List<Object?> get props => [];
}

/// Load (or refresh) the Home dashboard counts + follow-up list.
class DashboardLoadRequested extends DashboardEvent {
  const DashboardLoadRequested();
}
