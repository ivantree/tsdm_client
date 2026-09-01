import 'package:tsdm_client/extensions/universal_html.dart';
import 'package:tsdm_client/features/homepage/models/models.dart';
import 'package:universal_html/html.dart' as uh;

/// Parsed standard homepage and guide data.
final class HomepageData {
  /// Constructor.
  const HomepageData({required this.forumStatus, required this.pinnedThreadGroups, this.loggedUserInfo});

  /// Forum counters.
  final ForumStatus forumStatus;

  /// Logged user details, or null for anonymous pages.
  final LoggedUserInfo? loggedUserInfo;

  /// Latest thread groups from the guide page.
  final List<PinnedThreadGroup> pinnedThreadGroups;
}

PinnedThread? _parseGuideThread(uh.Element row) {
  final threadNode = row.querySelector('a.xst');
  final authorNode = row.querySelector('td.by cite > a');
  final threadUrl = threadNode?.attributes['href'];
  final threadTitle = threadNode?.text?.trim();
  final authorUrl = authorNode?.attributes['href'];
  final authorName = authorNode?.text?.trim();
  if (threadUrl == null || threadTitle == null || threadTitle.isEmpty) {
    return null;
  }
  if (authorUrl == null || authorName == null || authorName.isEmpty) {
    return null;
  }
  return PinnedThread(threadUrl: threadUrl, threadTitle: threadTitle, authorUrl: authorUrl, authorName: authorName);
}

/// Parse the standard forum homepage and latest-thread guide page.
HomepageData parseHomepageDocuments(
  uh.Document homeDocument,
  uh.Document guideDocument, {
  String? username,
  String? avatarUrl,
}) {
  final statusValues =
      homeDocument.querySelector('p.chart.z')?.querySelectorAll('em').map((e) => e.text).whereType<String>().toList() ??
      const [];
  final forumStatus = statusValues.length >= 3
      ? ForumStatus(todayCount: statusValues[0], yesterdayCount: statusValues[1], threadCount: statusValues[2])
      : const ForumStatus.empty();

  LoggedUserInfo? loggedUserInfo;
  if (username != null && username.isNotEmpty) {
    final welcomeNode = homeDocument.querySelector('div#wp.wp div#ct.wp.cl div#chart.bm.bw0.cl div.y');
    final relatedLinks =
        welcomeNode
            ?.querySelectorAll('a[href]')
            .map((e) => (e.firstEndDeepText()?.trim() ?? 'unknown', e.attributes['href']!))
            .toList() ??
        const [];
    loggedUserInfo = LoggedUserInfo(
      username: username,
      relatedLinkPairList: relatedLinks,
      avatarUrl:
          avatarUrl ?? homeDocument.querySelector('div#hd div.wp div.hdc.cl div#um div.avt.y a img')?.attributes['src'],
    );
  }

  final guideTitle =
      guideDocument.querySelector('div.bm_h h1.xs2')?.text?.trim() ??
      guideDocument.querySelector('h1.xs2')?.text?.trim() ??
      '最新发表';
  final threads = guideDocument
      .querySelectorAll('tbody[id^="normalthread_"], tbody[id^="stickthread_"]')
      .map(_parseGuideThread)
      .whereType<PinnedThread>()
      .toList();

  return HomepageData(
    forumStatus: forumStatus,
    loggedUserInfo: loggedUserInfo,
    pinnedThreadGroups: [PinnedThreadGroup(title: guideTitle, threadList: threads)],
  );
}
