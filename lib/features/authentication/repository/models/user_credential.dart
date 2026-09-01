part of 'models.dart';

/// User name field type, pair with password.
enum LoginField {
  /// Username
  username,

  /// Email address.
  email,

  /// Uid
  uid;

  @override
  String toString() {
    return switch (this) {
      LoginField.username => 'username',
      LoginField.email => 'email',
      LoginField.uid => 'uid',
    };
  }
}

/// Additional security question.
@MappableClass()
class SecurityQuestion with SecurityQuestionMappable {
  /// Constructor.
  const SecurityQuestion({required this.questionId, required this.answer});

  /// The question id of security question chose by user.
  final String questionId;

  /// The answer text that user texted.
  final String answer;
}

/// Login credential.
@MappableClass(generateMethods: GenerateMethods.stringify | GenerateMethods.copy | GenerateMethods.equals)
class UserCredential with UserCredentialMappable {
  /// Constructor.
  const UserCredential({
    required this.loginField,
    required this.loginFieldValue,
    required this.password,
    required this.captcha,
    this.securityQuestion,
  });

  /// Which name field stands for.
  final LoginField loginField;

  /// Name field value.
  final String loginFieldValue;

  /// Password.
  final String password;

  /// Captcha answer when required by the current challenge.
  final String captcha;

  /// Security question in web request.
  ///
  /// Can be null.
  final SecurityQuestion? securityQuestion;

  /// Build fields submitted to the current Discuz login form.
  Map<String, String> toFormData(LoginHash loginHash) {
    final m = <String, String>{
      ...loginHash.hiddenFields,
      'loginfield': loginField.toString(),
      'username': loginFieldValue,
      'password': password,
      'questionid': securityQuestion?.questionId ?? '0',
      'answer': securityQuestion?.answer ?? '',
      'cookietime': '2592000',
      'loginsubmit': 'true',
    };

    if (loginHash.requiresCaptcha) {
      m['seccodehash'] = loginHash.captchaHash!;
      m['seccodeverify'] = captcha;
    }

    return m;
  }
}
