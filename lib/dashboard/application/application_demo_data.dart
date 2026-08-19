/// Static demo data for the Application Details flow (Steps 2–5).
///
/// NOTE: placeholder data matching the mockups — no application-detail API is
/// wired yet. Replace these constants with values from the backend later.
class AppFlowDemo {
  AppFlowDemo._();

  static const String address =
      'Ram Appartment Block No 2, Chhota Tajbagh Chouk, Sakkardara, Nagpur, '
      'Maharashtra- 440024.';

  // Applicant / Co-applicant summary used across consent, KYC and submit.
  static const String applicantName = 'Neha Ajay Gupta';
  static const String applicantMobile = '+91 9876543210';
  static const String coApplicantName = 'Ajay Narayan Gupta';
  static const String coApplicantMobile = '+91 9876543211';
  static const String dealerName = 'ABC Motors';
  static const String applicationId = 'APP123456789';

  // Consent (Step 3) — section headings shown in the accordions.
  static const List<String> applicantConsentItems = [
    'Consent for Credit Bureau',
    'Term of Use',
    'Privacy Policy',
    'KYC & Documents Verification',
    'E-sign Consent',
  ];
  static const List<String> coApplicantConsentItems = [
    'Consent for Credit Bureau',
    'Term of Use',
    'Privacy Policy',
    'KYC & Documents Verification',
  ];
}
