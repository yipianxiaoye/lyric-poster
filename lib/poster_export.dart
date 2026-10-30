import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:archive/archive.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Keeps song titles readable while making them safe on Windows and Android.
String posterFileStem(String? songTitle) {
  var name = (songTitle ?? '')
      .trim()
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f\x7f]'), '_')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '');
  if (name.isEmpty) return '未命名歌曲';
  // Leave room for a page suffix and extension on filesystems with byte limits.
  final shortened = StringBuffer();
  var bytes = 0;
  for (final rune in name.runes) {
    final character = String.fromCharCode(rune);
    final length = utf8.encode(character).length;
    if (bytes + length > 180) break;
    shortened.write(character);
    bytes += length;
  }
  name = shortened.toString().replaceAll(RegExp(r'[. ]+$'), '');
  if (name.isEmpty) return '未命名歌曲';
  if (RegExp(
    r'^(CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³])(?:\.|$)',
    caseSensitive: false,
  ).hasMatch(name)) {
    name = '_$name';
  }
  return name;
}

String posterPngFileName(String? songTitle, {int page = 0, int pageCount = 1}) {
  if (pageCount < 1) {
    throw ArgumentError.value(pageCount, 'pageCount', 'Must be at least one.');
  }
  RangeError.checkValueInInterval(page, 0, pageCount - 1, 'page');
  final suffix = pageCount > 1 ? '-第${page + 1}页' : '';
  return '${posterFileStem(songTitle)}$suffix.png';
}

String posterPdfFileName(String? songTitle) =>
    '${posterFileStem(songTitle)}.pdf';

Uint8List posterPngArchive(List<Uint8List> pages, {String? songTitle}) {
  if (pages.isEmpty) throw ArgumentError('No poster pages to export.');
  final archive = Archive();
  for (var index = 0; index < pages.length; index++) {
    archive.addFile(
      ArchiveFile(
        posterPngFileName(songTitle, page: index, pageCount: pages.length),
        pages[index].length,
        pages[index],
      ),
    );
  }
  return ZipEncoder().encodeBytes(archive);
}

Future<Uint8List> posterPdf(List<Uint8List> pages, Size size) async {
  if (pages.isEmpty) throw ArgumentError('No poster pages to export.');
  final document = pw.Document();
  for (final png in pages) {
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(size.width, size.height),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.contain),
      ),
    );
  }
  return document.save();
}
