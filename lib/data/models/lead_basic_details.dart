/// Response of `POST /rm/lead-basic-details` — the read-only "Lead Details"
/// popup opened from the eye icon on a lead card. Wraps `data.basicDetails` +
/// `data.vehicleDetails`.
class LeadBasicDetails {
  const LeadBasicDetails({required this.basic, required this.vehicle});

  final LeadBasic basic;
  final LeadVehicle vehicle;

  factory LeadBasicDetails.fromResponse(Map<String, dynamic> json) {
    final data = json['data'] is Map
        ? Map<String, dynamic>.from(json['data'] as Map)
        : const <String, dynamic>{};
    Map<String, dynamic> sub(String key) => data[key] is Map
        ? Map<String, dynamic>.from(data[key] as Map)
        : const <String, dynamic>{};
    return LeadBasicDetails(
      basic: LeadBasic.fromJson(sub('basicDetails')),
      vehicle: LeadVehicle.fromJson(sub('vehicleDetails')),
    );
  }
}

/// `data.basicDetails` — leadId, name, contact, DOB, gender, address.
class LeadBasic {
  const LeadBasic({
    required this.leadId,
    required this.leadName,
    required this.mobileNumber,
    required this.emailAddress,
    required this.dateOfBirth,
    required this.gender,
    required this.address,
  });

  final String leadId;
  final String leadName;
  final String mobileNumber;
  final String emailAddress;
  final String dateOfBirth; // as sent by the API (e.g. "16/07/1994")
  final String gender;
  final String address;

  factory LeadBasic.fromJson(Map<String, dynamic> j) {
    String s(dynamic v) => v == null ? '' : v.toString();
    return LeadBasic(
      leadId: s(j['leadId']),
      leadName: s(j['leadName']),
      mobileNumber: s(j['mobileNumber']),
      emailAddress: s(j['emailAddress']),
      dateOfBirth: s(j['dateOfBirth']),
      gender: s(j['gender']),
      address: s(j['address']),
    );
  }
}

/// `data.vehicleDetails` — OEM, dealer, model, category.
class LeadVehicle {
  const LeadVehicle({
    required this.oem,
    required this.dealer,
    required this.vehicleModel,
    required this.vehicleCategory,
  });

  final String oem;
  final String dealer;
  final String vehicleModel;
  final String vehicleCategory;

  factory LeadVehicle.fromJson(Map<String, dynamic> j) {
    String s(dynamic v) => v == null ? '' : v.toString();
    return LeadVehicle(
      oem: s(j['oem']),
      dealer: s(j['dealer']),
      vehicleModel: s(j['vehicleModel']),
      vehicleCategory: s(j['vehicleCategory']),
    );
  }
}
