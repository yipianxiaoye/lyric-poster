import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'app_updates.dart';
import 'update_download_common.dart';

const _androidInstaller = MethodChannel('com.lyricposter/update_installer');

Future<UpdateInstallResult> downloadAndInstallUpdateImpl(
  ReleaseInfo release,
  UpdateDownloadSource source, {
  UpdateProgressCallback? onProgress,
}) async {
  final file = await downloadUpdateFile(
    release,
    source,
    onProgress: onProgress,
  );
  if (Platform.isWindows) {
    if (!file.path.toLowerCase().endsWith('.exe')) {
      throw const UpdateDownloadException('Windows 更新安装包格式不正确。');
    }
    final appDirectory = File(Platform.resolvedExecutable).parent.path;
    await Process.start(file.path, [
      '/VERYSILENT',
      '/SUPPRESSMSGBOXES',
      '/NORESTART',
      '/CLOSEAPPLICATIONS',
      '/RESTARTAPPLICATIONS',
      '/UPDATE=1',
      '/DIR=$appDirectory',
    ], mode: ProcessStartMode.detached);
    exit(0);
  }
  if (Platform.isAndroid) {
    if (!file.path.toLowerCase().endsWith('.apk')) {
      throw const UpdateDownloadException('Android 更新文件格式不正确。');
    }
    final status = await _androidInstaller.invokeMethod<String>('installApk', {
      'path': file.path,
    });
    if (status == 'permission_required') {
      return const UpdateInstallResult(
        '请在系统设置中允许词笺安装应用，返回后会自动打开安装界面。',
        permissionRequired: true,
      );
    }
    if (status != 'installer_launched') {
      throw const UpdateDownloadException('无法打开 Android 系统安装程序。');
    }
    return const UpdateInstallResult('已打开系统安装程序，请确认安装。');
  }
  throw const UpdateDownloadException('当前平台不支持应用内安装更新。');
}

Future<File> downloadUpdateFile(
  ReleaseInfo release,
  UpdateDownloadSource source, {
  http.Client? client,
  Directory? directory,
  UpdateProgressCallback? onProgress,
}) async {
  final downloadUrl = release.downloadUrl;
  final expectedSha256 = release.downloadSha256;
  if (downloadUrl == null || expectedSha256 == null) {
    throw const UpdateDownloadException('缺少可验证的安装包，已停止自动安装。');
  }
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedSha256)) {
    throw const UpdateDownloadException('更新校验信息无效。');
  }
  final filename = downloadUrl.pathSegments.isEmpty
      ? ''
      : Uri.decodeComponent(downloadUrl.pathSegments.last);
  if (!RegExp(
    r'^LyricPoster-[0-9.]+-windows-x64-setup\.exe$|^LyricPoster-[0-9.]+-android-universal\.apk$',
  ).hasMatch(filename)) {
    throw const UpdateDownloadException('更新文件名无效。');
  }
  if (!_isExpectedReleaseAsset(downloadUrl, release.tagName, filename)) {
    throw const UpdateDownloadException('更新下载地址不属于词笺官方发布资产。');
  }
  final targetDirectory = directory ?? await getTemporaryDirectory();
  final updateDirectory = Directory(
    '${targetDirectory.path}${Platform.pathSeparator}update',
  );
  await updateDirectory.create(recursive: true);
  final safeVersion = release.version.replaceAll(RegExp(r'[^0-9.]'), '_');
  final partial = File(
    '${updateDirectory.path}${Platform.pathSeparator}LyricPoster-$safeVersion.part',
  );
  final complete = File(
    '${updateDirectory.path}${Platform.pathSeparator}$filename',
  );
  final ownedClient = client == null;
  final requestClient = client ?? http.Client();
  final url = source == UpdateDownloadSource.github
      ? downloadUrl
      : Uri.parse('https://gh-proxy.com/$downloadUrl');

  try {
    final request = http.Request('GET', url)
      ..headers.addAll({
        'Accept': 'application/octet-stream',
        'User-Agent': 'LyricPoster/${release.version}',
      });
    final response = await requestClient
        .send(request)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw UpdateDownloadException(
        '下载失败（HTTP ${response.statusCode}），可切换下载源或打开发布页。',
      );
    }
    final total = response.contentLength;
    var received = 0;
    final sink = partial.openWrite();
    try {
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 60),
      )) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(UpdateDownloadProgress(received, total));
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (total != null && received != total) {
      throw const UpdateDownloadException('下载未完成，请重试。');
    }
    final actualSha256 = await sha256.bind(partial.openRead()).first;
    if (actualSha256.toString() != expectedSha256) {
      throw const UpdateDownloadException('安装包校验失败，文件可能在下载中损坏；请切换下载源重试。');
    }
    if (await complete.exists()) await complete.delete();
    return await partial.rename(complete.path);
  } on UpdateDownloadException {
    rethrow;
  } on TimeoutException {
    throw const UpdateDownloadException('下载超时，请检查网络或切换下载源。');
  } catch (_) {
    throw const UpdateDownloadException('无法下载更新，请检查网络或切换下载源。');
  } finally {
    if (await partial.exists()) await partial.delete();
    if (ownedClient) requestClient.close();
  }
}

bool _isExpectedReleaseAsset(Uri url, String tag, String filename) =>
    url.scheme == 'https' &&
    url.host == 'github.com' &&
    url.port == 443 &&
    url.userInfo.isEmpty &&
    !url.hasQuery &&
    !url.hasFragment &&
    url.pathSegments.length == 6 &&
    url.pathSegments[0] == 'yipianxiaoye' &&
    url.pathSegments[1] == 'lyric-poster' &&
    url.pathSegments[2] == 'releases' &&
    url.pathSegments[3] == 'download' &&
    url.pathSegments[4] == tag &&
    url.pathSegments[5] == filename;
