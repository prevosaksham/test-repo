import 'package:equatable/equatable.dart';

/// The authenticated user (the `user` object from /auth/verify-otp).
/// Parsing is tolerant: any field can be null/missing without throwing.
class UserModel extends Equatable {
  const UserModel({
    required this.id,
    required this.userCode,
    required this.keycloakId,
    required this.firstName,
    required this.middleName,
    required this.lastName,
    required this.email,
    required this.mobile,
    required this.address,
    required this.city,
    required this.state,
    required this.pinCode,
    required this.role,
    required this.isActive,
  });

  final int id;
  final String userCode;
  final String keycloakId;
  final String firstName;
  final String? middleName;
  final String lastName;
  final String email;
  final String mobile;
  final String? address;
  final String city;
  final String state;
  final String pinCode;
  final String role;
  final bool isActive;

  String get fullName =>
      [firstName, middleName, lastName].where((p) => (p ?? '').trim().isNotEmpty).join(' ');

  factory UserModel.fromJson(Map<String, dynamic> json) {
    String s(dynamic v) => v == null ? '' : v.toString();
    String? sn(dynamic v) => v?.toString();
    return UserModel(
      id: (json['id'] is num) ? (json['id'] as num).toInt() : int.tryParse(s(json['id'])) ?? 0,
      userCode: s(json['userCode']),
      keycloakId: s(json['keycloakId']),
      firstName: s(json['firstName']),
      middleName: sn(json['middleName']),
      lastName: s(json['lastName']),
      email: s(json['email']),
      mobile: s(json['mobile']),
      address: sn(json['address']),
      city: s(json['city']),
      state: s(json['state']),
      pinCode: s(json['pinCode']),
      role: s(json['role']),
      isActive: json['isActive'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'userCode': userCode,
        'keycloakId': keycloakId,
        'firstName': firstName,
        'middleName': middleName,
        'lastName': lastName,
        'email': email,
        'mobile': mobile,
        'address': address,
        'city': city,
        'state': state,
        'pinCode': pinCode,
        'role': role,
        'isActive': isActive,
      };

  UserModel copyWith({
    int? id,
    String? userCode,
    String? keycloakId,
    String? firstName,
    String? middleName,
    String? lastName,
    String? email,
    String? mobile,
    String? address,
    String? city,
    String? state,
    String? pinCode,
    String? role,
    bool? isActive,
  }) {
    return UserModel(
      id: id ?? this.id,
      userCode: userCode ?? this.userCode,
      keycloakId: keycloakId ?? this.keycloakId,
      firstName: firstName ?? this.firstName,
      middleName: middleName ?? this.middleName,
      lastName: lastName ?? this.lastName,
      email: email ?? this.email,
      mobile: mobile ?? this.mobile,
      address: address ?? this.address,
      city: city ?? this.city,
      state: state ?? this.state,
      pinCode: pinCode ?? this.pinCode,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
    );
  }

  /// Rebuild first/middle/last from a single display name so [fullName] reflects
  /// a locally-edited profile name. First word → firstName, last word →
  /// lastName, anything in between → middleName (empty when there isn't one).
  UserModel withFullName(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (parts.isEmpty) return this;
    final first = parts.first;
    final last = parts.length > 1 ? parts.last : '';
    final middle =
        parts.length > 2 ? parts.sublist(1, parts.length - 1).join(' ') : '';
    return copyWith(firstName: first, middleName: middle, lastName: last);
  }

  @override
  List<Object?> get props => [id, email, role];
}
