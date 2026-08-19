import 'package:equatable/equatable.dart';

/// Result of the Digio id-card analysis. We read two things:
///   1. Quality checks — `BLACK_AND_WHITE_IMAGE` + `BLUR_IMAGE` (PASS only when
///      both pass).
///   2. Detection — the first `detections[]` entry's `id_type` (AADHAAR / PAN /
///      VOTER_ID / DRIVING_LICENSE) and `detected_part` (FRONT / BACK), used to
///      verify the uploaded doc matches the slot it was uploaded into.
class DocQualityResult extends Equatable {
  const DocQualityResult({
    required this.blackWhitePass,
    required this.blurPass,
    required this.detectedIdType,
    required this.detectedPart,
    required this.verified,
    this.found = true,
  });

  final bool blackWhitePass;
  final bool blurPass;
  final String detectedIdType; // e.g. "AADHAAR" (uppercased, '' if none)
  final String detectedPart; // "FRONT" / "BACK" (uppercased, '' if none)
  final bool verified; // verification_result.verified (true if not present)
  final bool found; // were the two quality checks present in the response

  /// Quality passes only when both checks pass.
  bool get qualityPassed => blackWhitePass && blurPass;

  factory DocQualityResult.fromResponse(dynamic json) {
    final bw = _findResult(json, 'BLACK_AND_WHITE_IMAGE');
    final blur = _findResult(json, 'BLUR_IMAGE');
    final detection = _findFirstDetection(json);
    return DocQualityResult(
      blackWhitePass: bw == 'PASS',
      blurPass: blur == 'PASS',
      detectedIdType: _str(detection?['id_type']).toUpperCase(),
      detectedPart: _str(detection?['detected_part']).toUpperCase(),
      verified: _findVerified(json),
      found: bw != null || blur != null,
    );
  }

  /// Read `verification_result.verified`. Returns true when the block is absent
  /// (don't block on missing data) — only an explicit `false` fails.
  static bool _findVerified(dynamic node) {
    final m = _findFirstMapByKey(node, 'verification_result');
    if (m == null) return true;
    final v = m['verified'];
    return !(v == false || v == 'false');
  }

  static Map? _findFirstMapByKey(dynamic node, String key) {
    if (node is Map) {
      final v = node[key];
      if (v is Map) return v;
      for (final val in node.values) {
        final nested = _findFirstMapByKey(val, key);
        if (nested != null) return nested;
      }
    } else if (node is List) {
      for (final item in node) {
        final nested = _findFirstMapByKey(item, key);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  static String _str(dynamic v) => v == null ? '' : v.toString().trim();

  /// Deep-search the decoded JSON tree for [key] and return its nested
  /// `result` (uppercased), wherever it sits.
  static String? _findResult(dynamic node, String key) {
    if (node is Map) {
      for (final entry in node.entries) {
        if (entry.key == key && entry.value is Map) {
          final r = (entry.value as Map)['result'];
          if (r is String) return r.toUpperCase();
        }
        final nested = _findResult(entry.value, key);
        if (nested != null) return nested;
      }
    } else if (node is List) {
      for (final item in node) {
        final nested = _findResult(item, key);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  /// Find the first `detections` list anywhere in the tree and return its first
  /// element as a map (the detected id_type / part live here).
  static Map? _findFirstDetection(dynamic node) {
    if (node is Map) {
      final d = node['detections'];
      if (d is List && d.isNotEmpty && d.first is Map) return d.first as Map;
      for (final v in node.values) {
        final nested = _findFirstDetection(v);
        if (nested != null) return nested;
      }
    } else if (node is List) {
      for (final item in node) {
        final nested = _findFirstDetection(item);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  @override
  List<Object?> get props =>
      [blackWhitePass, blurPass, detectedIdType, detectedPart, verified, found];
}
