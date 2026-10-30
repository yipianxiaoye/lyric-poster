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
      final release = await _fetchLatest(installed);
      if (_disposed) return;
      latestRelease = release;
      lastCheckedAt = DateTime.now();
    } catch (failure) {
      if (!_disposed) error = _failure(failure).message;
    } finally {
      checking = false;
      _inFlight = null;
      if (!_disposed) notifyListeners();
      completion.complete();
    }
  }

  Future<ReleaseInfo?> _fetchLatest(InstalledVersion installed) async {
    late _UpdateFailure apiFailure;
    try {
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
      if (_disposed) return null;
      if (response.statusCode != 200) throw _httpFailure(response);
      final release = _readRelease(jsonDecode(utf8.decode(response.bodyBytes)));
      if (release == null) {
        throw const _UpdateFailure('暂时没有可用的正式版本。', noRelease: true);
      }
      return release;
    } catch (failure) {
      apiFailure = _failure(failure);
    }
    if (_disposed) return null;
    // GitHub's public API quota is shared by everyone using the same proxy.
    // The website's latest redirect provides an independent official route.
    try {
      return await _fetchLatestRedirect(installed);
    } catch (failure) {
      final webFailure = _failure(failure);
      if (apiFailure.noRelease) {
        throw webFailure.noRelease
            ? apiFailure
            : const _UpdateFailure('暂时无法确认最新正式版本，请检查网络后重试。');
      }
      throw apiFailure;
    }
  }

  Future<ReleaseInfo> _fetchLatestRedirect(InstalledVersion installed) async {
    final latestUrl = Uri.https(
      'github.com',
      '/yipianxiaoye/lyric-poster/releases/latest',
    );
    final request = http.Request('GET', latestUrl)
      ..followRedirects = false
      ..headers.addAll({
        'Accept': 'text/html',
        'User-Agent': 'LyricPoster/${installed.version}',
      });
    // Apply one deadline to both response headers and the response body stream.
    final response = await _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(timeout);
    if (![301, 302, 303, 307, 308].contains(response.statusCode)) {
      if (response.statusCode == 200) {
        throw const FormatException('Missing latest release redirect');
      }
      throw _httpFailure(response);
    }
    final location = response.headers['location'];
    if (location == null || location.isEmpty) {
      throw const FormatException('Missing latest release location');
    }
    final pageUrl = latestUrl.resolve(location);
    final tag = pageUrl.pathSegments.lastOrNull;
    if (tag == null || !_releaseUrl(pageUrl, 'tag', tag)) {
      throw const FormatException('Unexpected latest release location');
    }
    final version = _version(tag);
    if (version.isPreRelease) {
      throw const FormatException('Latest release is not stable');
    }
    return ReleaseInfo(
      version: '${version.major}.${version.minor}.${version.patch}',
      tagName: tag,
      title: '词笺 $tag',
      notes: '',
      pageUrl: pageUrl,
    );
  }

  static _UpdateFailure _httpFailure(http.Response response) {
    if (response.statusCode == 404) {
      return const _UpdateFailure('暂时没有可用的正式版本。', noRelease: true);
    }
    if (response.statusCode == 429 ||
        (response.statusCode == 403 &&
            response.headers['x-ratelimit-remaining']?.trim() == '0')) {
      return const _UpdateFailure('GitHub 公共更新服务的请求额度暂时用尽，发布页检查也未成功，请稍后重试。');
    }
    return _UpdateFailure(
      'GitHub 更新服务暂时不可用（HTTP ${response.statusCode}），请稍后重试。',
    );
  }

  static _UpdateFailure _failure(Object failure) => switch (failure) {
    _UpdateFailure() => failure,
    TimeoutException() => const _UpdateFailure('检查更新超时，请检查网络后重试。'),
    FormatException() => const _UpdateFailure('更新信息无法识别，请稍后重试。'),
    _ => const _UpdateFailure('无法连接更新服务，请检查网络后重试。'),
  };

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

class _UpdateFailure implements Exception {
  const _UpdateFailure(this.message, {this.noRelease = false});

  final String message;
  final bool noRelease;
}
