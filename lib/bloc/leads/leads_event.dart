part of 'leads_bloc.dart';

abstract class LeadsEvent extends Equatable {
  const LeadsEvent();

  @override
  List<Object?> get props => [];
}

/// Load the first page (also used for refresh and for a new search term).
class LeadsRequested extends LeadsEvent {
  const LeadsRequested({this.search = '', this.leadStatus = ''});
  final String search;
  final String leadStatus; // '' = all; else the selected status filter value

  @override
  List<Object?> get props => [search, leadStatus];
}

/// Load + append the next page (infinite scroll).
class LeadsNextPageRequested extends LeadsEvent {
  const LeadsNextPageRequested();
}

/// Jump to a specific page and REPLACE the list (numbered pagination on the
/// "View All" screen). [search] keeps the active search term across pages.
class LeadsPageSelected extends LeadsEvent {
  const LeadsPageSelected(this.page, {this.search = '', this.leadStatus = ''});
  final int page;
  final String search;
  final String leadStatus; // '' = all; else the selected status filter value

  @override
  List<Object?> get props => [page, search, leadStatus];
}
