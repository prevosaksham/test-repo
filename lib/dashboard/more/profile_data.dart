/// Profile fields shown on My Profile / Edit Profile.
///
/// NOTE: static demo data for now — there is no profile API wired yet. Replace
/// [demo] with a value built from the profile endpoint when it's available.
class ProfileData {
  const ProfileData({
    required this.fullName,
    required this.displayName,
    required this.mobile,
    required this.email,
    required this.dob,
    required this.gender,
    required this.status,
  });

  final String fullName; // "Rohan Anil Gaikwad"
  final String displayName; // header name "Rohan Gaikwad"
  final String mobile;
  final String email;
  final String dob; // dd/MM/yyyy
  final String gender;
  final String status; // e.g. "Active"

  ProfileData copyWith({
    String? fullName,
    String? mobile,
    String? email,
    String? dob,
  }) {
    return ProfileData(
      fullName: fullName ?? this.fullName,
      displayName: displayName,
      mobile: mobile ?? this.mobile,
      email: email ?? this.email,
      dob: dob ?? this.dob,
      gender: gender,
      status: status,
    );
  }

  static const ProfileData demo = ProfileData(
    fullName: 'Rohan Anil Gaikwad',
    displayName: 'Rohan Gaikwad',
    mobile: '+91 9876543210',
    email: 'rohan.gaikwad@nbfc.com',
    dob: '20/02/1990',
    gender: 'Male',
    status: 'Active',
  );

  /// Parse `/rm/get-profile`. Flexible about key names + an optional `data`
  /// wrapper (adjust here if the real response uses different keys).
  factory ProfileData.fromJson(Map<String, dynamic> json) {
    final raw = json['data'] is Map
        ? Map<String, dynamic>.from(json['data'] as Map)
        : json;
    String s(List<String> keys) {
      for (final k in keys) {
        final v = raw[k];
        if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
      }
      return '';
    }

    final first = s(['firstName', 'first_name', 'givenName', 'given_name']);
    final last = s(['lastName', 'last_name', 'familyName', 'family_name']);
    final joined = '$first $last'.trim();
    final full = s(['fullName', 'full_name', 'name']);
    final fullName = full.isNotEmpty ? full : joined;

    // status may be a string or an object { displayName/value }.
    final statusRaw = raw['status'] ?? raw['userStatus'] ?? raw['isActive'];
    String status;
    if (statusRaw is Map) {
      status = (statusRaw['displayName'] ?? statusRaw['value'] ?? '').toString();
    } else if (statusRaw is bool) {
      status = statusRaw ? 'Active' : 'Inactive';
    } else {
      status = (statusRaw ?? '').toString();
    }

    return ProfileData(
      fullName: fullName,
      displayName: full.isNotEmpty ? full : (joined.isNotEmpty ? joined : fullName),
      mobile: s(['mobile', 'mobileNo', 'mobileNumber', 'mobile_number', 'phone']),
      email: s(['email', 'emailAddress', 'email_address']),
      dob: s(['dob', 'dateOfBirth', 'date_of_birth', 'birthDate']),
      gender: s(['gender', 'sex']),
      status: status,
    );
  }
}
