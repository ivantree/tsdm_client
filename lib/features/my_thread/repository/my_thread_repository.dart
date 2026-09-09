import 'package:tsdm_client/exceptions/exceptions.dart';
import 'package:tsdm_client/instance.dart';
import 'package:tsdm_client/shared/providers/net_client_provider/net_client_provider.dart';
import 'package:universal_html/html.dart' as uh;
import 'package:universal_html/parsing.dart';

/// Repository of MyThread.
class MyThreadRepository {
  /// Fetch html document from [url].
  AsyncEither<uh.Document> fetchDocument(String url) => getIt.get<NetClientProvider>().get(url).andThenHttp((v) {
    final document = parseHtmlDocument(v.data as String);
    if (isLoginRequired(document)) {
      return taskLeft(MyThreadNeedLoginException());
    }
    return taskRight(document);
  });

  /// Whether [document] is a Discuz prompt asking the user to log in.
  static bool isLoginRequired(uh.Document document) {
    final message = document.querySelector('div#messagetext');
    final hasLoginEntry =
        message?.querySelector('a[href*="mod=logging"]') != null ||
        document.querySelector('form[action*="mod=logging"] input[name="username"]') != null;
    return message != null && hasLoginEntry;
  }
}
