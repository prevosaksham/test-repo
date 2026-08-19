part of 'followups_bloc.dart';

abstract class FollowupsEvent extends Equatable {
  const FollowupsEvent();
  @override
  List<Object?> get props => [];
}

/// Switch the active tab (call / visit) — reloads page 1 with the current
/// search term.
class FollowupsTabChanged extends FollowupsEvent {
  const FollowupsTabChanged(this.kind);
  final FollowupKind kind;
  @override
  List<Object?> get props => [kind];
}

/// Jump to a specific page number for the active tab + search.
class FollowupsPageRequested extends FollowupsEvent {
  const FollowupsPageRequested(this.page);
  final int page;
  @override
  List<Object?> get props => [page];
}

/// New search term — always reloads from page 1 (so a hit on page 4 surfaces
/// on page 1).
class FollowupsSearchChanged extends FollowupsEvent {
  const FollowupsSearchChanged(this.search);
  final String search;
  @override
  List<Object?> get props => [search];
}

/// Reload the current tab/page/search (pull-to-refresh / retry).
class FollowupsRefreshed extends FollowupsEvent {
  const FollowupsRefreshed();
}
