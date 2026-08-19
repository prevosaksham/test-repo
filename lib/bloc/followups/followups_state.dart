part of 'followups_bloc.dart';

enum FollowupsStatus { initial, loading, success, failure }

class FollowupsState extends Equatable {
  const FollowupsState({
    this.status = FollowupsStatus.initial,
    this.kind = FollowupKind.call,
    this.items = const [],
    this.search = '',
    this.pageNumber = 1,
    this.totalPages = 1,
    this.totalCount = 0,
    this.errorMessage,
  });

  final FollowupsStatus status;
  final FollowupKind kind; // active tab
  final List<FollowupItem> items;
  final String search;
  final int pageNumber;
  final int totalPages;
  final int totalCount;
  final String? errorMessage;

  bool get isLoading => status == FollowupsStatus.loading;

  FollowupsState copyWith({
    FollowupsStatus? status,
    FollowupKind? kind,
    List<FollowupItem>? items,
    String? search,
    int? pageNumber,
    int? totalPages,
    int? totalCount,
    String? errorMessage,
  }) {
    return FollowupsState(
      status: status ?? this.status,
      kind: kind ?? this.kind,
      items: items ?? this.items,
      search: search ?? this.search,
      pageNumber: pageNumber ?? this.pageNumber,
      totalPages: totalPages ?? this.totalPages,
      totalCount: totalCount ?? this.totalCount,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        status,
        kind,
        items,
        search,
        pageNumber,
        totalPages,
        totalCount,
        errorMessage,
      ];
}
