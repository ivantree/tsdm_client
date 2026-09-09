import 'package:fpdart/fpdart.dart';
import 'package:tsdm_client/constants/url.dart';
import 'package:tsdm_client/exceptions/exceptions.dart';
import 'package:tsdm_client/extensions/fp.dart';
import 'package:tsdm_client/instance.dart';
import 'package:tsdm_client/shared/providers/net_client_provider/net_client_provider.dart';
import 'package:tsdm_client/utils/logger.dart';
import 'package:universal_html/html.dart' as uh;
import 'package:universal_html/parsing.dart';

/// A repository that fetches the homepage html data from website.
final class ForumHomeRepository with LoggerMixin {
  static const _guideViews = ['newthread', 'new', 'hot', 'digest'];

  /// Cached document of forum homepage.
  uh.Document? _document;
  List<uh.Document>? _guideDocuments;

  /// Check has cached html [_document] or not.
  bool hasCache() => _document != null;

  /// Get the cached [_document].
  uh.Document? getCache() => _document;

  /// Check whether the guide pages are cached.
  bool hasGuideCache() => _guideDocuments?.isNotEmpty ?? false;

  /// Get the cached guide pages.
  List<uh.Document>? getGuideCache() => _guideDocuments;

  /// Fetch the home page of app from server.
  AsyncEither<uh.Document> fetchHomePage({bool force = false}) => AsyncEither(() async {
    debug('fetch home page');
    if (!force && _document != null) {
      debug('use cached home page');
      return right(_document!);
    }

    final docEither = await _fetchForumHome().run();
    if (docEither.isLeft()) {
      return left(docEither.unwrapErr());
    }

    _document = docEither.unwrap();
    debug('use fetched home page');
    return right(_document!);
  });

  /// Fetch the topic page of app from server.
  AsyncEither<uh.Document> fetchTopicPage({bool force = false}) => AsyncEither(() async {
    debug('fetch topics page');
    if (!force && _document != null) {
      debug('use cached topics page');
      return right(_document!);
    }
    final e = await _fetchForumHome().run();
    if (e.isLeft()) {
      return left(e.unwrapErr());
    }
    _document = e.unwrap();
    return right(_document!);
  });

  /// Fetch the standard guide pages.
  AsyncEither<List<uh.Document>> fetchGuidePages({bool force = false}) => AsyncEither(() async {
    if (!force && (_guideDocuments?.isNotEmpty ?? false)) {
      return right(_guideDocuments!);
    }

    final documents = <uh.Document>[];
    AppException? firstError;
    for (final view in _guideViews) {
      final response = await _fetchDocument(
        '$baseUrl/forum.php',
        queryParameters: {'mod': 'guide', 'view': view},
      ).run();
      if (response.isLeft()) {
        final error = response.unwrapErr();
        firstError ??= error;
        warning('failed to fetch $view guide page: $error');
        continue;
      }
      documents.add(response.unwrap());
    }
    if (documents.isEmpty) {
      return left(firstError ?? HttpRequestFailedException(null));
    }

    _guideDocuments = documents;
    return right(_guideDocuments!);
  });

  /// Fetch the [homePage] of forum.
  ///
  /// # Exception
  ///
  /// * [HttpHandshakeFailedException] if GET request failed.
  AsyncEither<uh.Document> _fetchForumHome() => _fetchDocument(homePage);

  AsyncEither<uh.Document> _fetchDocument(String url, {Map<String, dynamic>? queryParameters}) => AsyncEither(() async {
    final netClient = getIt.get<NetClientProvider>();
    AppException? lastError;
    for (final host in [baseHost, baseHostAlt]) {
      final requestUrl = Uri.parse(url).replace(host: host).toString();
      final result = await netClient
          .get(requestUrl, queryParameters: queryParameters)
          .mapHttp((response) => parseHtmlDocument(response.data as String))
          .run();
      if (result.isRight()) {
        return right(result.unwrap());
      }
      lastError = result.unwrapErr();
    }
    return left(lastError ?? HttpRequestFailedException(null));
  });
}
