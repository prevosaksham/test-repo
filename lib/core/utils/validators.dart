/// Small form-validation helpers.
class Validators {
  Validators._();

  // HTML5-style email pattern: a sensible, strict-enough check for real inputs.
  static final RegExp _email = RegExp(
    r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$",
  );

  /// True when [value] is a well-formed email address.
  static bool isValidEmail(String value) => _email.hasMatch(value.trim());
}
