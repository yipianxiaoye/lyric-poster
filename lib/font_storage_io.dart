import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

Future<File> _file(String id) async {
  final root = await getApplicationSupportDirectory();
  final directory = Directory('${root.path}${Platform.pathSeparator}fonts');
  await directory.create(recursive: true);
  return File('${directory.path}${Platform.pathSeparator}$id.font');
}

Future<void> writeFont(String id, Uint8List bytes) async =>
    (await _file(id)).writeAsBytes(bytes, flush: true);
Future<Uint8List> readFont(String id) async => (await _file(id)).readAsBytes();
