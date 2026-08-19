part of 'leads_bloc.dart';

enum LeadsStatus { initial, loading, success, failure }

class LeadsState extends Equatable {
  const LeadsState({
    this.status = LeadsStatus.initial,
    this.items = const [],
    this.pageNumber = 1,
    this.totalPages = 1,
    this.totalCount = 0,
    this.isLoadingMore = false,
    this.search = '',
    this.leadStatus = '',
    this.errorMessage,
  });

  final LeadsStatus status;
  final List<LeadItem> items;
  final int pageNumber;
  final int totalPages;
  final int totalCount;
  final bool isLoadingMore;
  final String search;
  final String leadStatus; // active status filter ('' = all)
  final String? errorMessage;

  bool get isLoading => status == LeadsStatus.loading;
  bool get hasMore => pageNumber < totalPages;

  LeadsState copyWith({
    LeadsStatus? status,
    List<LeadItem>? items,
    int? pageNumber,
    int? totalPages,
    int? totalCount,
    bool? isLoadingMore,
    String? search,
    String? leadStatus,
    String? errorMessage,
  }) {
    return LeadsState(
      status: status ?? this.status,
      items: items ?? this.items,
      pageNumber: pageNumber ?? this.pageNumber,
      totalPages: totalPages ?? this.totalPages,
      totalCount: totalCount ?? this.totalCount,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      search: search ?? this.search,
      leadStatus: leadStatus ?? this.leadStatus,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        status,
        items,
        pageNumber,
        totalPages,
        totalCount,
        isLoadingMore,
        search,
        leadStatus,
        errorMessage,
      ];
}
