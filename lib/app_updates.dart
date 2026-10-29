import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';

class InstalledVersion {
  const InstalledVersion({required this.version, required this.buildNumber});

  final String version, buildNumber;

  String get display => buildNumber.isEmpty ? version : '$version+$buildNumber';

  static Future<InstalledVersion> load() async {
    final info = await PackageInfo.fromPlatform();
    return InstalledVersion(
      version: info.version,
      buildNumber: info.buildNumber,
    );
  }
}

class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.tagName,
    required this.title,
    required this.notes,
    required this.pageUrl,
    this.downloadUrl,
  });

  final String version, tagName, title, notes;
  final Uri pageUrl;
  final Uri? downloadUrl;
}

/// Checks the public stable release without authentication or local user data.
class UpdateController extends ChangeNotifier {
  UpdateController({
    http.Client? client,
    Future<InstalledVersion> Function()? versionLoader,
    TargetPlatform? platform,
    this.timeout = const Duration(seconds: 12),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _versionLoader = versionLoader ?? InstalledVersion.load,
       _platform = platform ?? defaultTargetPlatform;

  final http.Client _client;
  final bool _ownsClient;
  final Future<InstalledVersion> Function() _versionLoader;
  final TargetPlatform _platform;
  final Duration timeout;
  Future<InstalledVersion>? _versionLoad;
  Future<void>? _inFlight;
  bool _disposed = false;

  InstalledVersion? installedVersion;
  ReleaseInfo? latestRelease;
  bool checking = false;
  String? error;
  DateTime? lastCheckedAt;

  bool get updateAvailable =>
      !checking &&
      error == null &&
      installedVersion != null &&
      latestRelease != null &&
      _version(latestRelease!.version) > _version(installedVersion!.version);

  Future<InstalledVersion> _readInstalledVersion() async {
    if (installedVersion != null) return installedVersion!;
    final pending = _versionLoad ??= _versionLoader().timeout(timeout);
    try {
      final result = await pending;
      _version(result.version);
      if (!_disposed) installedVersion = result;
      return result;
    } finally {
      if (identical(_versionLoad, pending)) _versionLoad = null;
    }
  }

  /// Loads version text without initiating an update request.
  Future<void> loadInstalledVersion() async {
    if (_disposed || installedVersion != null) return;
    try {
      await _readInstalledVersion();
    } catch (_) {
      if (!_disposed && !checking) error = '无法读取当前版本，请稍后重试。';
    }
    if (!_disposed) notifyListeners();
  }

  /// A manual check joins an in-progress startup check rather than duplicating it.
  Future<void> check() {
    if (_disposed) return Future.value();
    if (_inFlight != null) return _inFlight!;
    final completion = Completer<void>();
    _inFlight = completion.future;
    checking = true;
    error = null;
    notifyListeners();
    unawaited(_runCheck(completion));
    return completion.future;
  }

  Future<void> _runCheck(Completer<void> completion) async {
    try {
      final installed = await _readInstalledVersion();
      if (_disposed) return;
      final response = await _client
          .get(
            Uri.https(
              'api.github.com',
              '/repos/yipianxiaoye/lyric-poster/releases/latest',
            ),
            headers: {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'LyricPoster/${installed.version}',
              'X-GitHub-Api-Version': '2022-11-28',
            },
          )
          .timeout(timeout);
      if (_disposed) return;
      if (response.statusCode == 404) {
        latestRelease = null;
        error = '暂时没有可用的正式版本。';
      } else if (response.statusCode == 403 || response.statusCode == 429) {
        error = '检查更新过于频繁，请稍后重试。';
      } else if (response.statusCode != 200) {
        error = '暂时无法检查更新（HTTP ${response.statusCode}），请稍后重试。';
      } else {
        latestRelease = _readRelease(
          jsonDecode(utf8.decode(response.bodyBytes)),
        );
        lastCheckedAt = DateTime.now();
      }
    } on TimeoutException {
      if (!_disposed) error = '检查更新超时，请检查网络后重试。';
    } on FormatException {
      if (!_disposed) error = '更新信息无法识别，请稍后重试。';
    } catch (_) {
      if (!_disposed) error = '无法连接更新服务，请检查网络后重试。';
    } finally {
      checking = false;
      _inFlight = null;
      if (!_disposed) notifyListeners();
      completion.complete();
    }
  }

  ReleaseInfo? _readRelease(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['draft'] is! bool ||
        value['prerelease'] is! bool) {
      throw const FormatException('Invalid release');
    }
    if (value['draft'] == true || value['prerelease'] == true) return null;
    final tag = value['tag_name'];
    final page = value['html_url'];
    if (tag is! String || page is! String) {
      throw const FormatException('Missing release metadata');
    }
    final parsed = _version(tag);
    if (parsed.isPreRelease) return null;
    final version = '${parsed.major}.${parsed.minor}.${parsed.patch}';
    final pageUrl = Uri.tryParse(page);
    if (!_releaseUrl(pageUrl, 'tag', tag)) {
      throw const FormatException('Unexpected release URL');
    }
    final assetName = switch (_platform) {
      TargetPlatform.windows => 'LyricPoster-$version-windows-x64.zip',
      TargetPlatform.android => 'LyricPoster-$version-android-universal.apk',
      _ => null,
    };
    Uri? downloadUrl;
    final assets = value['assets'];
    if (assets is! List) throw const FormatException('Invalid release assets');
    if (assetName != null) {
      for (final asset in assets) {
        if (asset is! Map<String, dynamic> ||
            asset['name'] != assetName ||
            asset['state'] != 'uploaded' ||
            asset['browser_download_url'] is! String) {
          continue;
        }
        final uri = Uri.tryParse(asset['browser_download_url'] as String);
        if (_releaseUrl(uri, 'download', tag, assetName)) {
          downloadUrl = uri;
          break;
        }
      }
    }
    return ReleaseInfo(
      version: version,
      tagName: tag,
      title: value['name'] is String && (value['name'] as String).isNotEmpty
          ? value['name'] as String
          : '词笺 $tag',
      notes: value['body'] is String ? value['body'] as String : '',
      pageUrl: pageUrl!,
      downloadUrl: downloadUrl,
    );
  }

  static Version _version(String value) {
    final normalized = value.startsWith('v') ? value.substring(1) : value;
    // Build metadata identifies packages, not a newer public version.
    Version.parse(normalized);
    return Version.parse(normalized.split('+').first);
  }

  static bool _releaseUrl(
    Uri? uri,
    String kind,
    String tag, [
    String? assetName,
  ]) {
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'github.com' ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return false;
    }
    final expected = [
      'yipianxiaoye',
      'lyric-poster',
      'releases',
      kind,
      tag,
      ?assetName,
    ];
    return listEquals(uri.pathSegments, expected);
  }

  @override
  void dispose() {
    _disposed = true;
    if (_ownsClient) _client.close();
    super.dispose();
  }
}
