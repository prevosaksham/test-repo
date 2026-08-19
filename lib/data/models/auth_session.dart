import 'package:equatable/equatable.dart';
import 'user_model.dart';

/// The full login model returned by /auth/verify-otp: the user plus tokens.
/// This is what we persist so the user stays logged in across app restarts.
class AuthSession extends Equatable {
  const AuthSession({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.refreshExpiresIn,
  });

  final UserModel user;
  final String accessToken;
  final String refreshToken;
  final int expiresIn;
  final int refreshExpiresIn;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final userJson = json['user'];
    return AuthSession(
      user: UserModel.fromJson(
        userJson is Map ? Map<String, dynamic>.from(userJson) : <String, dynamic>{},
      ),
      accessToken: json['accessToken']?.toString() ?? '',
      refreshToken: json['refreshToken']?.toString() ?? '',
      expiresIn: (json['expiresIn'] is num)
          ? (json['expiresIn'] as num).toInt()
          : int.tryParse(json['expiresIn']?.toString() ?? '') ?? 0,
      refreshExpiresIn: (json['refreshExpiresIn'] is num)
          ? (json['refreshExpiresIn'] as num).toInt()
          : int.tryParse(json['refreshExpiresIn']?.toString() ?? '') ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'user': user.toJson(),
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiresIn': expiresIn,
        'refreshExpiresIn': refreshExpiresIn,
      };

  AuthSession copyWith({
    UserModel? user,
    String? accessToken,
    String? refreshToken,
    int? expiresIn,
    int? refreshExpiresIn,
  }) {
    return AuthSession(
      user: user ?? this.user,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      expiresIn: expiresIn ?? this.expiresIn,
      refreshExpiresIn: refreshExpiresIn ?? this.refreshExpiresIn,
    );
  }

  @override
  List<Object?> get props => [user, accessToken, refreshToken];
}
