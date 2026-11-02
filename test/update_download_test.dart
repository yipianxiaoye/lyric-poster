import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyric_poster/app_updates.dart';
import 'package:lyric_poster/update_download.dart';
import 'package:lyric_poster/update_download_io.dart' show downloadUpdateFile;

void main() {
  final bytes = Uint8List.fromList(
    List<int>.generate(4096, (index) => index % 256),
  );

  ReleaseInfo release(String digest) => ReleaseInfo(
    version: '1.6.0',
    tagName: 'v1.6.0',
    title: '词笺 v1.6.0',
    notes: '更新内容',
    pageUrl: Uri.parse(
      'https://github.com/yipianxiaoye/lyric-poster/releases/tag/v1.6.0',
    ),
    downloadUrl: Uri.parse(
      'https://github.com/yipianxiaoye/lyric-poster/releases/download/v1.6.0/LyricPoster-1.6.0-windows-x64-setup.exe',
    ),
    downloadSha256: digest,
  );

  test('从 GitHub 下载后验证 SHA-256 并保存完整安装包', () async {
    final directory = await Directory.systemTemp.createTemp(
      'lyric-poster-update-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        release(sha256.convert(bytes).toString()).downloadUrl.toString(),
      );
      return http.Response.bytes(bytes, 200);
    });
    addTearDown(client.close);
    final progress = <UpdateDownloadProgress>[];

    final file = await downloadUpdateFile(
      release(sha256.convert(bytes).toString()),
      UpdateDownloadSource.github,
      client: client,
      directory: directory,
      onProgress: progress.add,
    );

    expect(file.existsSync(), isTrue);
    expect(await file.readAsBytes(), bytes);
    expect(progress.last.receivedBytes, bytes.length);
  });

  test('镜像下载使用配置镜像并拒绝不匹配的安装包', () async {
    final directory = await Directory.systemTemp.createTemp(
      'lyric-poster-update-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://gh-proxy.com/https://github.com/yipianxiaoye/lyric-poster/releases/download/v1.6.0/LyricPoster-1.6.0-windows-x64-setup.exe',
      );
      return http.Response.bytes(bytes, 200);
    });
    addTearDown(client.close);

    await expectLater(
      downloadUpdateFile(
        release('0' * 64),
        UpdateDownloadSource.mirror,
        client: client,
        directory: directory,
      ),
      throwsA(isA<UpdateDownloadException>()),
    );
    expect(
      Directory('${directory.path}${Platform.pathSeparator}update').listSync(),
      isEmpty,
    );
  });

  test('拒绝无校验信息或外站下载地址', () async {
    final directory = await Directory.systemTemp.createTemp(
      'lyric-poster-update-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final unsafe = ReleaseInfo(
      version: '1.6.0',
      tagName: 'v1.6.0',
      title: '词笺 v1.6.0',
      notes: '',
      pageUrl: Uri.parse(
        'https://github.com/yipianxiaoye/lyric-poster/releases/tag/v1.6.0',
      ),
      downloadUrl: Uri.parse(
        'https://example.com/LyricPoster-1.6.0-windows-x64-setup.exe',
      ),
      downloadSha256: 'a' * 64,
    );
    await expectLater(
      downloadUpdateFile(
        unsafe,
        UpdateDownloadSource.github,
        directory: directory,
      ),
      throwsA(isA<UpdateDownloadException>()),
    );
    expect(directory.listSync(), isEmpty);
  });
}
