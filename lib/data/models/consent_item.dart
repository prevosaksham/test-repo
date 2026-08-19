/// The full `/consent/list` response — the Terms header ([title] +
/// [description]) plus the consent [items].
class ConsentData {
  const ConsentData({
    required this.title,
    required this.description,
    required this.items,
  });
  final String title;
  final String description;
  final List<ConsentItem> items;
}

/// One consent/terms entry from `GET /consent/list` (`data[]`). Shown as an
/// accordion on the Applicant/Co-Applicant Consent screen: [displayName] is the
/// title and [content] is the body text.
class ConsentItem {
  const ConsentItem({
    required this.id,
    required this.displayName,
    required this.consentKey,
    required this.content,
    required this.order,
    required this.isMandatory,
  });

  final String id;
  final String displayName;
  final String consentKey;
  final String content;
  final int order;
  final bool isMandatory;

  factory ConsentItem.fromJson(Map<String, dynamic> j) {
    String s(dynamic v) => v == null ? '' : v.toString();
    int i(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('${v ?? ''}') ?? 0;
    }

    return ConsentItem(
      id: s(j['id']),
      displayName: s(j['displayName']),
      consentKey: s(j['consentKey']),
      content: s(j['content']),
      order: i(j['order']),
      isMandatory: j['isMandatory'] == true,
    );
  }
}
