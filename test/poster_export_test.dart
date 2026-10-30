import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_poster/poster_export.dart';

void main() {
  test('单页 PNG 和全部 PDF 使用歌曲名', () {
    expect(posterPngFileName('风与远方'), '风与远方.png');
    expect(posterPdfFileName('风与远方'), '风与远方.pdf');
    expect(posterPdfFileName('  风与远方  '), '风与远方.pdf');
  });

  test('保留中文、空格、括号及 Unicode 歌名', () {
    expect(posterPngFileName('后来 (Live) 🎵'), '后来 (Live) 🎵.png');
    expect(posterPdfFileName('蓝.蓝'), '蓝.蓝.pdf');
  });

  test('多页 PNG 使用歌名和当前页码，避免不同页覆盖', () {
    expect(posterPngFileName('后来', pageCount: 3), '后来-第1页.png');
    expect(posterPngFileName('后来', page: 1, pageCount: 3), '后来-第2页.png');
    expect(posterPngFileName('后来', page: 2, pageCount: 3), '后来-第3页.png');
    expect(posterPdfFileName('后来'), '后来.pdf');
  });

  test('空歌名及只有句点或空白的歌名使用明确默认名', () {
    for (final title in [null, '', '  \r\n\t ', '.', '..', ' ... ']) {
      expect(posterPdfFileName(title), '未命名歌曲.pdf', reason: '$title');
    }
  });

  test('过滤 Windows 非法字符与控制字符，不能形成路径', () {
    final name = posterPngFileName('歌曲<>:"/\\|?*\u0000\n结束');
    expect(name, startsWith('歌曲'));
    expect(name, endsWith('结束.png'));
    expect(name, isNot(matches(RegExp(r'[<>:"/\\|?*\x00-\x1f\x7f]'))));
    expect(posterPdfFileName('../后来/现场版'), '.._后来_现场版.pdf');
    expect(posterPdfFileName('歌名...   '), '歌名.pdf');
  });

  test('Windows 设备保留名仍然可以保存', () {
    for (final title in [
      'CON',
      'nul',
      'PRN',
      'AUX',
      'COM1',
      'LPT9',
      'NUL.txt',
    ]) {
      expect(posterPdfFileName(title), '_$title.pdf');
    }
    expect(posterPdfFileName('CONCERT'), 'CONCERT.pdf');
  });

  test('超长中文和表情歌名按完整字符截短，为后缀保留空间', () {
    for (final title in ['歌' * 200, '🎵' * 100, 'a' * 300]) {
      final stem = posterFileStem(title);
      expect(stem, isNotEmpty);
      expect(utf8.encode(stem).length, lessThanOrEqualTo(180));
      expect(stem.runes, isNot(contains(0xfffd)));
      expect(
        utf8.encode(posterPngFileName(title, page: 99, pageCount: 100)).length,
        lessThan(255),
      );
    }
  });

  test('拒绝不存在的导出页码', () {
    expect(() => posterPngFileName('歌曲', pageCount: 0), throwsArgumentError);
    expect(() => posterPngFileName('歌曲', page: -1), throwsRangeError);
    expect(
      () => posterPngFileName('歌曲', page: 2, pageCount: 2),
      throwsRangeError,
    );
  });

  test('超长标题截短后重新检查空文件名和 Windows 保留名', () {
    expect(posterPdfFileName('CON${' ' * 180}x'), '_CON.pdf');
    expect(posterPngFileName('${'.' * 181}x'), '未命名歌曲.png');
  });

  test('PNG 压缩包中每页文件也使用歌名和页码且内容不变', () {
    final pages = [
      Uint8List.fromList([1, 2]),
      Uint8List.fromList([3, 4, 5]),
    ];
    final archive = ZipDecoder().decodeBytes(
      posterPngArchive(pages, songTitle: '后来'),
    );
    expect(archive.files.map((file) => file.name), [
      '后来-第1页.png',
      '后来-第2页.png',
    ]);
    for (var i = 0; i < pages.length; i++) {
      expect(archive.files[i].content, orderedEquals(pages[i]));
    }
    final single = ZipDecoder().decodeBytes(
      posterPngArchive([pages.first], songTitle: '后来'),
    );
    expect(single.files.single.name, '后来.png');
    expect(() => posterPngArchive([]), throwsArgumentError);
  });
}
