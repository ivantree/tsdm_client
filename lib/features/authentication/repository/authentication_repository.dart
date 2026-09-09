import 'dart:async';
import 'dart:convert';
import 'dart:io' if (dart.libaray.js) 'package:web/web.dart';

import 'package:fpdart/fpdart.dart';
import 'package:rxdart/rxdart.dart';
import 'package:tsdm_client/constants/url.dart';
import 'package:tsdm_client/exceptions/exceptions.dart';
import 'package:tsdm_client/extensions/fp.dart';
import 'package:tsdm_client/extensions/string.dart';
import 'package:tsdm_client/extensions/universal_html.dart';
import 'package:tsdm_client/features/authentication/repository/internal/login_parser.dart';
import 'package:tsdm_client/features/authentication/repository/models/models.dart';
import 'package:tsdm_client/features/settings/repositories/settings_repository.dart';
import 'package:tsdm_client/instance.dart';
import 'package:tsdm_client/shared/models/models.dart';
import 'package:tsdm_client/shared/providers/cookie_provider/cookie_provider.dart';
import 'package:tsdm_client/shared/providers/net_client_provider/net_client_provider.dart';
import 'package:tsdm_client/shared/providers/providers.dart';
import 'package:tsdm_client/shared/providers/storage_provider/storage_provider.dart';
import 'package:tsdm_client/utils/logger.dart';
import 'package:universal_html/html.dart' as uh;
import 'package:universal_html/parsing.dart';

/// Repository of authentication.
///
/// Provides login, logout.
///
/// **Need to call dispose.**
class AuthenticationRepository with LoggerMixin {
  /// Constructor.
  AuthenticationRepository({UserLoginInfo? user}) : _authedUser = user;

  static const _checkAuthUrl = '$baseUrl/home.php?mod=spacecp&ac=profile';
  static const _loginFormUrl = '$baseUrl/member.php?mod=logging&action=login';
  static const _logoutBaseUrl = '$baseUrl/member.php?mod=logging&action=logout&formhash=';
  static final _formHashRe = RegExp(r'formhash" value="(?<FormHash>\w+)"');

  /// Url to check authentication status using v2 API.
  static const _checkAuthUrlV2 = '$baseUrl/home.php?mobile=yes&tsdmapp=1&mod=space&do=profile';

  static String _buildLogoutUrl(String formHash) {
    return '$_logoutBaseUrl$formHash';
  }

  /// Provide a stream of [AuthStatus].
  ///
  /// Be aware that the data contained in stream is not the state in auth bloc.
  final _controller = BehaviorSubject<AuthStatus>();

  UserLoginInfo? _authedUser;
  CookieProvider? _loginCookie;
  NetClientProvider? _loginClient;

  /// The current logged user.
  UserLoginInfo? get currentUser => _authedUser;

  /// Authentication status stream.
  Stream<AuthStatus> get status => _controller.asBroadcastStream();

  /// Dispose the resources.
  Future<void> dispose() async {
    await _controller.close();
  }

  /// Fetch the standard Discuz login challenge.
  AsyncEither<LoginHash> fetchHash() => AsyncEither(() async {
    _loginCookie = getIt.get<CookieProvider>(instanceName: ServiceKeys.empty);
    _loginClient = NetClientProvider.buildNoCookie(cookie: _loginCookie);
    final response = await _loginClient!.get(_loginFormUrl).run();
    if (response.isLeft()) {
      return left(response.unwrapErr());
    }
    if (response.unwrap().statusCode != HttpStatus.ok) {
      return left(HttpRequestFailedException(response.unwrap().statusCode));
    }
    return parseDiscuzLoginForm(response.unwrap().data as String);
  });

  /// Fetch the captcha image using the current login challenge session.
  AsyncEither<List<int>> fetchCaptchaImage(String imageUrl) => AsyncEither(() async {
    final client = _loginClient;
    if (client == null) {
      return left(LoginInvalidFormHashException());
    }
    final response = await client.getImage(imageUrl).run();
    if (response.isLeft()) {
      return left(response.unwrapErr());
    }
    return right(List<int>.from(response.unwrap().data as List<dynamic>));
  });

  /// Login with password and other parameters in [credential].
  ///
  /// Will not change authentication status if failed to login.
  AsyncVoidEither loginWithPassword(LoginHash loginHash, UserCredential credential) => AsyncVoidEither(() async {
    debug('login with passwd');
    await _markUnauthenticated();
    // When login with password, use an empty and injected cookie when
    // performing login request. Because :
    //
    // * Want to use a pure and clean cookie when start login, to avoid
    //   using current authed user's cookie.
    // * Control when and what user info to save with the cookie stored in
    //   it, so that the token is successfully saved in storage.
    final cookie = _loginCookie;
    final netClient = _loginClient;
    if (cookie == null || netClient == null) {
      return left(LoginInvalidFormHashException());
    }

    final respEither = await netClient.postForm(loginHash.actionUrl, data: credential.toFormData(loginHash)).run();
    if (respEither.isLeft()) {
      return left(respEither.unwrapErr());
    }

    final resp = respEither.unwrap();
    if (resp.statusCode != HttpStatus.ok) {
      return left(HttpRequestFailedException(resp.statusCode));
    }

    final loginError = parseDiscuzLoginError(resp.data as String);
    if (loginError != null) {
      return left(loginError);
    }

    final profileEither = await netClient.get(_checkAuthUrl).run();
    if (profileEither.isLeft()) {
      return left(profileEither.unwrapErr());
    }
    final profileResponse = profileEither.unwrap();
    if (profileResponse.statusCode != HttpStatus.ok) {
      return left(HttpRequestFailedException(profileResponse.statusCode));
    }
    final userInfo = parseLoggedUserInfo(parseHtmlDocument(profileResponse.data as String));
    if (userInfo == null) {
      return left(LoginUserInfoNotFoundException());
    }

    await cookie.updateUserInfo(userInfo);
    await cookie.saveCookieToStorage();
    await getIt.get<CookieProvider>().loadCookieFromStorage(userInfo);
    await _markAuthenticated(userInfo);
    _loginCookie = null;
    _loginClient = null;
    debug('end login with success');
    return rightVoid();
  });

  /// Parse logged user info from html [document].
  AsyncVoidEither loginWithDocument(uh.Document document) => AsyncVoidEither(() async {
    // Do NOT mark as unauthenticated here because auth with document is
    // only used as a verification of a token that intend to be valid. It's
    // outside the regular login progress.
    final userInfo = parseLoggedUserInfo(document);
    if (userInfo == null) {
      debug('failed to login with document: user info not found');
      return left(LoginUserInfoNotFoundException());
    }

    // Here we get complete user info.
    await getIt.get<CookieProvider>().saveCookieToStorage();
    await _markAuthenticated(userInfo);

    debug('login with document: user $userInfo');
    return rightVoid();
  });

  /// Logout the current user.
  ///
  /// Check authentication status first then try to logout.
  /// Do nothing if already unauthenticated.
  AsyncVoidEither logout() => AsyncVoidEither(() async {
    if (_authedUser == null) {
      return rightVoid();
    }
    final netClient = NetClientProvider.build(
      userLoginInfo: UserLoginInfo(username: _authedUser!.username, uid: _authedUser!.uid),
    );
    final respEither = await netClient.get(_checkAuthUrl).run();
    if (respEither.isLeft()) {
      return left(respEither.unwrapErr());
    }
    final resp = respEither.unwrap();
    if (resp.statusCode != HttpStatus.ok) {
      return left(HttpRequestFailedException(resp.statusCode));
    }
    final document = parseHtmlDocument(resp.data as String);
    final userInfo = parseLoggedUserInfo(document);
    if (userInfo == null) {
      // Not logged in.
      await _markUnauthenticated();
      return rightVoid();
    }
    final formHash = _formHashRe.firstMatch(document.body?.innerHtml ?? '')?.namedGroup('FormHash');
    if (formHash == null) {
      return left(LogoutFormHashNotFoundException());
    }

    final logoutRespEither = await netClient.get(_buildLogoutUrl(formHash)).run();
    if (logoutRespEither.isLeft()) {
      return left(logoutRespEither.unwrapErr());
    }
    final logoutResp = logoutRespEither.unwrap();
    if (logoutResp.statusCode != HttpStatus.ok) {
      return left(HttpRequestFailedException(logoutResp.statusCode));
    }
    final logoutDocument = parseHtmlDocument(logoutResp.data as String);
    final logoutMessage = logoutDocument.getElementById('messagetext');
    if (logoutMessage == null || !logoutMessage.innerHtmlEx().contains('已退出')) {
      // TODO: Here we'd better to check the failed reason.
      return left(LogoutFailedException());
    }

    getIt.get<CookieProvider>().clearUserInfoAndCookie();
    await getIt.get<StorageProvider>().deleteCookieByUid(_authedUser!.uid!);
    await _markUnauthenticated();
    return rightVoid();
  });

  /// Switch to another user described in [userInfo].
  ///
  /// Return [SwitchUserNotAuthedException] if failed.
  AsyncVoidEither switchUser(UserLoginInfo userInfo) => AsyncVoidEither(() async {
    if (!await getIt.get<CookieProvider>().loadCookieFromStorage(userInfo)) {
      return left(LoginInvalidCredentialException());
    }
    final resp = await getIt.get<NetClientProvider>().get(_checkAuthUrlV2).run();
    if (resp.isLeft()) {
      return left(resp.unwrapErr());
    }

    final result = jsonDecode(resp.unwrap().data as String) as Map<String, dynamic>;
    if (result['status'] != 0) {
      error(
        'failed to switch user to uid=${"${userInfo.uid}".obscured(4)}, '
        'status=${result["status"]}, '
        'message=${result["message"]}',
      );
      return left(SwitchUserNotAuthedException());
    }

    // Succeed.
    // Here we get complete user info.
    await getIt.get<CookieProvider>().saveCookieToStorage();
    await _markAuthenticated(userInfo);

    debug('login with document: user $userInfo');
    return rightVoid();
  });

  /// Parse the login result.
  ///
  /// Do nothing if login succeed.
  // SyncVoidEither _mapLoginResult(LoginResult loginResult) =>
  //     switch (loginResult) {
  //       LoginResult.success => rightVoid(),
  //       LoginResult.incorrectCaptcha => left(LoginIncorrectCaptchaException()),
  //       LoginResult.invalidUsernamePassword =>
  //         left(LoginInvalidCredentialException()),
  //       LoginResult.incorrectQuestionOrAnswer =>
  //         left(LoginIncorrectSecurityQuestionException()),
  //       LoginResult.attemptLimit => left(LoginAttemptLimitException()),
  //     LoginResult.otherError => left(LoginOtherErrorException('other error')),
  //     LoginResult.unknown => left(LoginOtherErrorException('unknown result')),
  //     };

  Future<void> _saveLoggedUserInfo(UserLoginInfo userInfo) async {
    debug('save logged user info: $userInfo');
    // Save logged user info in settings.
    final settings = getIt.get<SettingsRepository>();
    await settings.setValue<String>(SettingsKeys.loginUsername, userInfo.username!);
    await settings.setValue<int>(SettingsKeys.loginUid, userInfo.uid!);
    if (userInfo.email != null) {
      await settings.setValue<String>(SettingsKeys.loginEmail, userInfo.email!);
    } else {
      await settings.deleteValue(SettingsKeys.loginEmail);
    }

    _authedUser = userInfo;
  }

  /// All steps need to execute when state should change to authed except saving
  /// cookies because sometimes the cookie provider holding latest authed cookie
  /// is not the one global wide.
  ///
  /// This function does something that need to be completed before auth state
  /// changes so that all auth stream subscribers are using the correct data in
  /// authed state.
  Future<void> _markAuthenticated(UserLoginInfo userInfo) async {
    // Save user info to memory and storage.
    await _saveLoggedUserInfo(userInfo);
    // Clear cookie.
    await getIt<CookieProvider>().updateUserInfo(
      UserLoginInfo(username: userInfo.username, uid: userInfo.uid, email: userInfo.email),
    );
    // Do NOT save cookie to storage here, because it's not always the normal
    // global cookie provider doing the auth work, maybe another local cookie in
    // some scope.
    // Instead, save cookie outside this function when necessary.
    // await getIt<CookieProvider>().saveCookieToStorage();
    // Finally change state to authed.
    _controller.add(AuthStatusAuthed(userInfo));
  }

  /// All actions need to execute when state should change to unauthenticated.
  ///
  /// This function does something that need to be completed before auth state
  /// changes so that all auth stream subscribers are using the correct data in
  /// unauthenticated state.
  Future<void> _markUnauthenticated() async {
    final settings = getIt.get<SettingsRepository>();
    await settings.deleteValue(SettingsKeys.loginUsername);
    await settings.deleteValue(SettingsKeys.loginUid);
    await settings.deleteValue(SettingsKeys.loginEmail);
    _authedUser = null;
    _controller.add(const AuthStatusNotAuthed());
  }
}
