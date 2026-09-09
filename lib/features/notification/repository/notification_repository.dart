import 'dart:io' if (dart.libaray.js) 'package:web/web.dart';

import 'package:fpdart/fpdart.dart';
import 'package:rxdart/rxdart.dart';
import 'package:tsdm_client/constants/url.dart';
import 'package:tsdm_client/exceptions/exceptions.dart';
import 'package:tsdm_client/extensions/uri.dart';
import 'package:tsdm_client/features/notification/models/models.dart';
import 'package:tsdm_client/instance.dart';
import 'package:tsdm_client/shared/providers/net_client_provider/net_client_provider.dart';
import 'package:tsdm_client/utils/logger.dart';
import 'package:universal_html/html.dart' as uh;
import 'package:universal_html/parsing.dart';

/// Repository of notification.
final class NotificationRepository with LoggerMixin {
  static const _emptyPersonalMessageText = '当前没有相应的短消息';

  /// Provide a stream of [NotificationInfoState] those are fetched from server.
  ///
  /// Carries fetch result and fetched info if any.
  final _controller = BehaviorSubject<NotificationInfoState>();

  /// Stream of fetched notification fetching status.
  Stream<NotificationInfoState> get status => _controller.asBroadcastStream();

  /// Build the url for notification v2 API.
  ///
  /// [timestamp] is optional timestamp of last call on this API.
  String _buildNotificationV2Url({int? timestamp}) {
    final now = DateTime.now();
    final int? argTimestamp;
    // The input [timestamp] is in seconds.
    final time = timestamp != null ? DateTime.fromMillisecondsSinceEpoch(timestamp * 1000) : now;
    if (timestamp != null && 0 <= now.difference(time).inDays && now.difference(time).inDays <= 3) {
      argTimestamp = timestamp;
    } else {
      argTimestamp = now.add(const Duration(days: -3)).millisecondsSinceEpoch ~/ 1000;
    }

    return '$baseUrl/plugin.php?mobile=yes&tsdmapp=1&id=Kahrpba:usernotify&last_updated=$argTimestamp';
  }

  /// Fetch the html document of notice detail page.
  AsyncEither<(uh.Document, String? page)> fetchDocument(String url) => AsyncEither(
    () async => switch (await getIt.get<NetClientProvider>().get(url).run()) {
      Left(:final value) => left(value),
      Right(:final value) when value.statusCode != HttpStatus.ok => left(HttpRequestFailedException(value.statusCode)),
      Right(:final value) => right((
        parseHtmlDocument(value.data as String),
        value.realUri.tryGetQueryParameters()?['page'],
      )),
    },
  );

  /// Fetch all personal messages from server page.
  AsyncEither<List<PersonalMessage>> fetchPersonalMessage() => AsyncEither(
    () async => switch (await getIt.get<NetClientProvider>().get(personalMessageUrl).run()) {
      Left(:final value) => left(value),
      Right(:final value) when value.statusCode != HttpStatus.ok => left(HttpRequestFailedException(value.statusCode)),
      Right(:final value) => right(
        parseHtmlDocument(value.data as String)
            .querySelectorAll('form#deletepmform > div > dl')
            .map(PersonalMessage.fromDl)
            .whereType<PersonalMessage>()
            .toList(),
      ),
    },
  );

  /// Fetch all broadcast messages from server page.
  AsyncEither<List<BroadcastMessage>> fetchBroadMessage() => getIt
      .get<NetClientProvider>()
      .get(broadcastMessageUrl)
      .mapHttp(
        (v) => parseHtmlDocument(v.data as String)
            .querySelectorAll('form#deletepmform > div > dl')
            .map(BroadcastMessage.fromDl)
            .whereType<BroadcastMessage>()
            .toList(),
      );

  /// Fetch all kinds of notification using API v2.
  ///
  /// [timestamp] is the last time call this api (in seconds).
  /// [uid] is the user id of whom to do the fetch action.
  AsyncVoidEither fetchNotificationV2({required int uid, int? timestamp}) => AsyncVoidEither(() async {
    _controller.add(const NotificationInfoStateLoading());
    final netClient = getIt.get<NetClientProvider>();
    final apiResult = await netClient.get(_buildNotificationV2Url(timestamp: timestamp)).run();
    if (apiResult case Right(:final value) when value.statusCode == HttpStatus.ok) {
      try {
        final info = switch (value.data) {
          final String data => NotificationV2Mapper.fromJson(data),
          final Map<String, dynamic> data => NotificationV2Mapper.fromMap(data),
          _ => throw const FormatException('unexpected notification response'),
        };
        _controller.add(NotificationInfoStateSuccess(uid, info));
        return rightVoid();
      } on FormatException {
        warning('notification plugin returned a non-JSON response; falling back to the standard message page');
      }
    }

    final pageResult = await netClient.get(personalMessageUrl).run();
    final AppException? error;
    switch (pageResult) {
      case Left(:final value):
        error = value;
      case Right(:final value) when value.statusCode != HttpStatus.ok:
        error = HttpRequestFailedException(value.statusCode);
      case Right(:final value):
        final document = parseHtmlDocument(value.data as String);
        final isEmpty = document
            .querySelectorAll('div.emp')
            .any((node) => node.innerText.trim() == _emptyPersonalMessageText);
        if (isEmpty) {
          _controller.add(
            NotificationInfoStateSuccess(
              uid,
              const NotificationV2(
                status: 0,
                noticeList: [],
                personalMessageList: [],
                broadcastMessageList: [],
              ),
            ),
          );
          return rightVoid();
        }
        error = HttpRequestFailedException(value.statusCode);
    }

    _controller.add(const NotificationInfoStateFailure());
    return left(error);
  });

  /// Dispose the repo.
  Future<void> dispose() async {
    await _controller.close();
  }
}
