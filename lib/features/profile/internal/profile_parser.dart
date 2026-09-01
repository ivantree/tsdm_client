import 'package:tsdm_client/extensions/universal_html.dart';
import 'package:universal_html/html.dart' as uh;

/// Finds the profile content root in legacy and Discuz X5 templates.
uh.Element? findProfileRoot(uh.Document document) {
  return document.querySelector('div#pprl > div.bm.bbda') ?? document.querySelector('div.bm_c.u_profile');
}

/// Finds the profile avatar URL in legacy and Discuz X5 templates.
String? findProfileAvatarUrl(uh.Document document, uh.Element profileRoot) {
  return document.querySelector('div#wp.wp div#ct.ct2 div.sd div.hm > p > a > img')?.imageUrl() ??
      profileRoot.querySelector('div.avt img')?.imageUrl();
}
