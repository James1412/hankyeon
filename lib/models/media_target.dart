/// 미디어의 표시 정보와 제어에 필요한 주소를 분리합니다.
abstract class MediaTarget {
  const MediaTarget();
  String get identity;
  String get sourceLabel;
}

/// Safari와 다른 WebExtension의 공통 탭·프레임·페이지 식별자입니다.
abstract class WebMediaTarget extends MediaTarget {
  final String mediaId;
  final int tabId;
  final int frameId;
  final String tabUrl;
  final String mediaUrl;
  const WebMediaTarget({
    required this.mediaId,
    required this.tabId,
    required this.frameId,
    required this.tabUrl,
    required this.mediaUrl,
  });
  String get addressIdentity => '$tabId/$frameId/$mediaId/$tabUrl/$mediaUrl';
  @override
  String get sourceLabel => Uri.tryParse(tabUrl)?.host ?? 'Browser';
  Map<String, Object> toMap() => {
    'mediaId': mediaId,
    'tabId': tabId,
    'frameId': frameId,
    'tabUrl': tabUrl,
    'mediaUrl': mediaUrl,
  };
}

class SafariMediaTarget extends WebMediaTarget {
  const SafariMediaTarget({
    required super.mediaId,
    required super.tabId,
    required super.frameId,
    required super.tabUrl,
    required super.mediaUrl,
  });
  @override
  String get identity => 'safari/$addressIdentity';
}

class BrowserMediaTarget extends WebMediaTarget {
  final String clientId;
  final String browserName;
  const BrowserMediaTarget({
    required this.clientId,
    required this.browserName,
    required super.mediaId,
    required super.tabId,
    required super.frameId,
    required super.tabUrl,
    required super.mediaUrl,
  });
  @override
  String get identity => 'browser/$clientId/$addressIdentity';
  @override
  String get sourceLabel => '$browserName · ${super.sourceLabel}';
}

/// A native application has no tab, URL, or browser playback controls.
class NativeAppTarget extends MediaTarget {
  final String bundleID;
  final String name;
  const NativeAppTarget({required this.bundleID, required this.name});
  @override
  String get identity => 'app/$bundleID';
  @override
  String get sourceLabel => name;
}
