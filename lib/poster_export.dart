import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:archive/archive.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Uint8List posterPngArchive(List<Uint8List> pages) {
  if (pages.isEmpty) throw ArgumentError('No poster pages to export.');
  final archive = Archive();
  for (var index = 0; index < pages.length; index++) {
    archive.addFile(
      ArchiveFile(
        'lyric-poster-${(index + 1).toString().padLeft(3, '0')}.png',
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
