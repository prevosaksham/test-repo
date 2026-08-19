import 'dart:convert';
import 'dart:typed_data';

/// One previously-uploaded document from `POST /application/details`
/// (`data.applicantDocs[]` / `data.coApplicantDocs[]`).
class UploadedDoc {
  const UploadedDoc({
    required this.id,
    required this.documentCode,
    required this.fileName,
    required this.originalName,
    required this.mimeType,
    required this.fileSize,
    required this.thumbnail,
    required this.dataUri,
  });

  final String id; // documentId — used to fetch the full file on demand
  final String documentCode; // AADHAAR_FRONT, PAN, CO_PAN, …
  final String fileName; // stored name (uuid.jpg)
  final String originalName; // user's original file name (kapilsir.jpg)
  final String mimeType; // image/jpeg, application/pdf, …
  final int fileSize; // bytes
  final String thumbnail; // small base64 preview for the list (may be empty)
  final String dataUri; // "data:image/jpeg;base64,…" (legacy/full — may be empty)

  bool get isPdf => mimeType.toLowerCase().contains('pdf');

  /// Decoded FULL image bytes from [dataUri] (base64). Null when there's no
  /// data or it can't be decoded. Still used by the read-only view screens that
  /// receive the full base64 inline.
  Uint8List? get bytes => _decodeBase64(dataUri);

  /// Decoded small THUMBNAIL bytes from [thumbnail] (base64). Null when empty
  /// or undecodable. Used by the Upload screen's lightweight list previews.
  Uint8List? get thumbnailBytes => _decodeBase64(thumbnail);

  /// The thumbnail as a network URL when the API sends one (new `/application/
  /// details` shape). '' when it's inline base64 (legacy) or empty — render
  /// [thumbnailBytes] then.
  String get thumbnailUrl {
    final t = thumbnail.trim();
    return t.startsWith('http') ? t : '';
  }

  /// Decode a (possibly data-URI-prefixed) base64 string to bytes.
  static Uint8List? _decodeBase64(String raw) {
    if (raw.isEmpty) return null;
    final i = raw.indexOf('base64,');
    final b64 = i >= 0 ? raw.substring(i + 7) : raw;
    try {
      return base64Decode(b64.trim());
    } catch (_) {
      return null;
    }
  }

  factory UploadedDoc.fromJson(Map<String, dynamic> json) {
    String s(dynamic v) => v == null ? '' : v.toString();
    int toInt(dynamic v) => v is int ? v : int.tryParse(s(v)) ?? 0;
    // Newer responses put the file fields at the top level and add a small
    // `thumbnail`; older ones nest the file fields under `fileData`. Prefer the
    // top-level value, fall back to fileData so both shapes parse cleanly.
    final fd = json['fileData'];
    final file =
        fd is Map ? Map<String, dynamic>.from(fd) : const <String, dynamic>{};
    String pick(String key) {
      final top = json[key];
      if (top != null && top.toString().isNotEmpty) return top.toString();
      return s(file[key]);
    }

    return UploadedDoc(
      id: s(json['id']),
      documentCode: s(json['documentCode']),
      fileName: pick('fileName'),
      originalName: pick('originalName'),
      mimeType: pick('mimeType'),
      fileSize: toInt(json['fileSize'] ?? file['fileSize']),
      thumbnail: s(json['thumbnail']),
      dataUri: pick('dataUri'),
    );
  }
}

/// The full file returned on demand by `POST /application/document`
/// (`data.fileData.dataUri` base64). The details list now carries only a small
/// thumbnail, so the full image/PDF is fetched lazily when the user views it.
class DocumentFile {
  const DocumentFile({
    required this.mimeType,
    required this.fileName,
    required this.bytes,
  });

  final String mimeType;
  final String fileName;
  final Uint8List? bytes;

  bool get isPdf => mimeType.toLowerCase().contains('pdf');

  factory DocumentFile.fromResponse(Map<String, dynamic> json) {
    String s(dynamic v) => v == null ? '' : v.toString();
    final data = json['data'];
    final d = data is Map
        ? Map<String, dynamic>.from(data)
        : const <String, dynamic>{};
    final fd = d['fileData'];
    final file =
        fd is Map ? Map<String, dynamic>.from(fd) : const <String, dynamic>{};
    return DocumentFile(
      mimeType: s(file['mimeType']),
      fileName: s(file['fileName']),
      bytes: UploadedDoc._decodeBase64(s(file['dataUri'])),
    );
  }
}

/// The two document lists from the application-details response.
class ApplicationDocs {
  const ApplicationDocs({required this.applicant, required this.coApplicant});

  final List<UploadedDoc> applicant;
  final List<UploadedDoc> coApplicant;

  factory ApplicationDocs.fromDetails(Map<String, dynamic> json) {
    // Response: { data: { applicantDocs: [], coApplicantDocs: [] } }
    final data = json['data'];
    final d = data is Map ? Map<String, dynamic>.from(data) : json;
    List<UploadedDoc> parse(dynamic raw) => (raw is List ? raw : const [])
        .whereType<Map>()
        .map((e) => UploadedDoc.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return ApplicationDocs(
      applicant: parse(d['applicantDocs']),
      coApplicant: parse(d['coApplicantDocs']),
    );
  }
}
