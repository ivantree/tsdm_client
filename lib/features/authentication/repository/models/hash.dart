part of 'models.dart';

/// A group of login hash used in login or logout progress.
@MappableClass()
class LoginHash with LoginHashMappable {
  /// Constructor.
  const LoginHash({
    required this.formHash,
    required this.loginHash,
    required this.actionUrl,
    required this.hiddenFields,
    required this.requiresCaptcha,
    this.captchaHash,
    this.captchaImageUrl,
  });

  /// Form hash.
  final String formHash;

  /// Login hash.
  ///
  /// Seems not used.
  final String loginHash;

  /// Form submission target provided by Discuz.
  final String actionUrl;

  /// Hidden fields provided by Discuz for this login challenge.
  final Map<String, String> hiddenFields;

  /// Whether this challenge requires a captcha answer.
  final bool requiresCaptcha;

  /// Captcha challenge identifier.
  final String? captchaHash;

  /// Captcha image source for this challenge.
  final String? captchaImageUrl;
}
