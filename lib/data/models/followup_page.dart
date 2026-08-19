import 'package:equatable/equatable.dart';
import 'followup_item.dart';

/// One page of `GET /followup/list`. The API wraps the rows + pagination
/// metadata under `data`: `{followups[], total_count, page_number,
/// page_limit, total_pages}`.
class FollowupPage extends Equatable {
  const FollowupPage({
    required this.items,
    required this.pageNumber,
    required this.pageLimit,
    required this.totalPages,
    required this.totalCount,
  });

  final List<FollowupItem> items;
  final int pageNumber;
  final int pageLimit;
  final int totalPages;
  final int totalCount;

  static const empty = FollowupPage(
    items: [],
    pageNumber: 1,
    pageLimit: 10,
    totalPages: 1,
    totalCount: 0,
  );

  /// Parses the `data` object. `requestedPage` is the fallback page number when
  /// the API omits it. Tolerates the legacy shape where `data` is a bare list.
  factory FollowupPage.fromJson(dynamic data, {required int requestedPage}) {
    int i(dynamic v, {int fb = 0}) =>
        v is int ? v : int.tryParse(v?.toString() ?? '') ?? fb;

    final raw = (data is Map) ? data['followups'] : data;
    final items = (raw is List)
        ? raw
            .whereType<Map>()
            .map((e) => FollowupItem.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <FollowupItem>[];

    final map = data is Map ? data : const {};
    return FollowupPage(
      items: items,
      pageNumber: i(map['page_number'], fb: requestedPage),
      pageLimit: i(map['page_limit'], fb: 10),
      totalPages: i(map['total_pages'], fb: 1),
      totalCount: i(map['total_count'], fb: items.length),
    );
  }

  @override
  List<Object?> get props =>
      [items, pageNumber, pageLimit, totalPages, totalCount];
}
