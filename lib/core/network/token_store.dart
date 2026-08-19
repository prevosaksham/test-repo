/// Tiny in-memory holder for the auth/login token. Swap for secure storage
/// (flutter_secure_storage) when persistence across app restarts is needed.
class TokenStore {
  TokenStore._();
  static final TokenStore instance = TokenStore._();

  /// Bearer token after a full (post-OTP) login.
  String? authToken;

  /// Short-lived token returned by /auth/login, used for the OTP step.
  String? loginToken;

  void clear() {
    authToken = null;
    loginToken = null;
  }
}
