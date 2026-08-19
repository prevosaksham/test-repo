import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/lead_preview.dart';

/// Persists getPreview's `applicationStages` per lead (in SharedPreferences) so
/// later flow screens (e.g. Customer Consent → save-term) can read the real
/// stage `id` + `stageType` for a stage. getPreview's stage shape (`id`) differs
/// from `/application/details` (`stageId`), so we keep the getPreview copy here.
class ApplicationStageStore {
  ApplicationStageStore._();
  static final ApplicationStageStore instance = ApplicationStageStore._();

  String _key(String leadId) => 'app_stages_$leadId';

  /// Save the application stages for [leadId] (called when the Application
  /// Process flow starts).
  Future<void> save(String leadId, List<StageItem> stages) async {
    if (leadId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = stages
        .map((s) => {
              'id': s.id,
              'stageName': s.stageName,
              'stageType': s.stageType,
              'order': s.order,
              'completed': s.completed,
              'current': s.current,
              'locked': s.locked,
            })
        .toList();
    await prefs.setString(_key(leadId), jsonEncode(list));
  }

  /// Load the saved stages for [leadId] (empty when nothing was saved).
  Future<List<StageItem>> load(String leadId) async {
    if (leadId.isEmpty) return const [];
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(leadId));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map>()
          .map((e) => StageItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// The saved stage whose name matches [name] (case-insensitive), else null.
  Future<StageItem?> stageByName(String leadId, String name) async {
    final stages = await load(leadId);
    final n = name.trim().toLowerCase();
    for (final s in stages) {
      if (s.stageName.trim().toLowerCase() == n) return s;
    }
    return null;
  }
}
