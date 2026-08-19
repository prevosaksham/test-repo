/// Formats a date of birth for display as **dd-MM-yyyy** (e.g. 21-11-1993).
///
/// Accepts yyyy-MM-dd / ISO datetime, or day-first dd-MM-yyyy / dd/MM/yyyy.
/// Empty stays empty; an unrecognised shape is returned unchanged.
String formatDob(String? raw) {
  final v = (raw ?? '').trim();
  if (v.isEmpty) return '';
  final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(v);
  if (iso != null) {
    return '${iso.group(3)}-${iso.group(2)}-${iso.group(1)}';
  }
  final dmy = RegExp(r'^(\d{1,2})[-/](\d{1,2})[-/](\d{4})').firstMatch(v);
  if (dmy != null) {
    return '${dmy.group(1)!.padLeft(2, '0')}-'
        '${dmy.group(2)!.padLeft(2, '0')}-${dmy.group(3)}';
  }
  return v;
}
