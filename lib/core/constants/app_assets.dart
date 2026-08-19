/// Central registry of image/asset paths.
///
/// Reference assets through these constants everywhere (never hard-code the
/// string path in a widget). To swap a brand asset, replace the file in
/// `assets/images/` (keep the same name) or change the path here once — every
/// screen that uses it updates automatically.
class AppAssets {
  AppAssets._();

  static const String _images = 'assets/images';

  /// SFL "Satin Finserv Limited" wordmark — shown in the white circle on the
  /// splash screen and every auth screen header (via [SflLogo]).
  static const String sflLogo = '$_images/sfl_logo.png';

  /// Green success badge (check inside a circle) — shown on the password
  /// reset success screen.
  static const String successCheck = '$_images/success_check.png';

  /// Static map preview shown above the Field Investigation "Capture Current
  /// Location" button.
  static const String sendLocationMap = '$_images/sendlocationimg.png';

  /// Photo-gallery placeholder (shown in empty selfie / image upload slots).
  static const String photoGallery = '$_images/photogallery.png';

  static const String _icons = 'assets/icons';

  // Bottom navigation.
  static const String navHome = '$_icons/nav_home.svg';
  static const String navMyLeads = '$_icons/nav_myleads.svg';
  static const String navReports = '$_icons/nav_reports.svg';
  static const String navMore = '$_icons/nav_more.svg';

  // Header. (Avatar is a photo, so it stays a PNG.)
  static const String profileAvatar = '$_icons/profile_avatar.png';
  static const String notification = '$_icons/notification.svg';
  static const String search = '$_icons/search.svg';
  static const String filter = '$_icons/filter.svg';

  // Dashboard stat cards.
  static const String totalLeads = '$_icons/total_leads.svg';
  static const String convertedLeads = '$_icons/converted_leads.svg';
  static const String rejectedLeads = '$_icons/rejected_leads.svg';
  static const String conversionRate = '$_icons/convertionrate.svg';

  // "More" menu.
  static const String myProfile = '$_icons/my_profile.svg';
  static const String changePassword = '$_icons/change_password.svg';
  static const String terms = '$_icons/terms.svg';
  static const String privacy = '$_icons/privacy.svg';
  static const String darkMode = '$_icons/dark_mode.svg';
  static const String logout = '$_icons/logout.svg';

  // Lead interaction (Customer Interaction flow).
  static const String calling = '$_icons/calling.svg';
  static const String schedule = '$_icons/schedule.svg';
  static const String document = '$_icons/document.svg';

  // Application details flow.
  static const String consentLink = '$_icons/consent_link.svg';
  static const String submitApplication = '$_icons/submit_application.svg';

  // View Lead (timeline + application details).
  static const String circleUser = '$_icons/circle_user.svg';
  static const String documentSigned = '$_icons/document_signed.svg';
  static const String calendar = '$_icons/calendar.svg';
}
