import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/auth_session.dart';

/// Persists the logged-in [AuthSession] (user + tokens) so the user stays
/// logged in across app restarts.
///
/// Backed by **flutter_secure_storage** — encrypted on both platforms:
///   • Android → Keystore-backed EncryptedSharedPreferences
///   • iOS     → Keychain
/// The public API (load/save/clear/current/isLoggedIn) is unchanged, so no
/// caller needs to change.
class AuthStorage {
  AuthStorage._();
  static final AuthStorage instance = AuthStorage._();

  static const String _key = 'auth_session';

  // v10+: Android encryption is secure by default (Keystore-backed custom
  // ciphers); iOS uses the Keychain. first_unlock keeps the token readable
  // after the first device unlock (so background refresh works).
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  AuthSession? _cached;
  AuthSession? get current => _cached;
  bool get isLoggedIn => _cached != null && _cached!.accessToken.isNotEmpty;

  /// Bumps on every session change (login / logout / profile edit). Widgets that
  /// show session data (e.g. the dashboard header name) listen to this and read
  /// [current] so they refresh live. A plain `ValueNotifier<AuthSession>`
  /// wouldn't fire on a name/mobile edit because AuthSession/UserModel are
  /// Equatable on id/email/token only — hence a revision counter that always
  /// changes.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  void _bump() => revision.value++;

  /// Load the saved session into memory (call once at startup).
  Future<AuthSession?> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return null;
    try {
      _cached = AuthSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      _cached = null;
    }
    _bump();
    return _cached;
  }

  Future<void> save(AuthSession session) async {
    _cached = session;
    await _storage.write(key: _key, value: jsonEncode(session.toJson()));
    _bump();
  }

  Future<void> clear() async {
    _cached = null;
    await _storage.delete(key: _key);
    _bump();
  }

  /// Patch the locally-stored session's user after a profile edit so the new
  /// name / mobile show everywhere that reads the session (dashboard header,
  /// home). No-op when there's no active session.
  Future<void> updateProfile({String? fullName, String? mobile}) async {
    final session = _cached;
    if (session == null) return;
    var user = session.user;
    if (fullName != null && fullName.trim().isNotEmpty) {
      user = user.withFullName(fullName);
    }
    if (mobile != null && mobile.trim().isNotEmpty) {
      user = user.copyWith(mobile: mobile.trim());
    }
    await save(session.copyWith(user: user));
  }
}
