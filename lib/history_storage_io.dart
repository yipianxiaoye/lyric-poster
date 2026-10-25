import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'history_storage.dart';

class LocalHistoryStorage implements HistoryStorage {
  Future<File> _file(String key) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(key)) {
      throw ArgumentError.value(key, 'key');
    }
    final root = await getApplicationSupportDirectory();
    final directory = Directory('${root.path}${Platform.pathSeparator}history');
    await directory.create(recursive: true);
    return File('${directory.path}${Platform.pathSeparator}$key.json');
  }

  @override
  Future<String?> read(String key) async {
    final file = await _file(key);
    if (await file.exists()) return file.readAsString();
    return null;
  }

  @override
  Future<void> write(String key, String value) async {
    final file = await _file(key);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(value, flush: true);
    // Replace only after a complete write, so interrupted writes retain the
    // previous valid document. All writes are serialized by HistoryStore.
    await temporary.rename(file.path);
  }

  @override
  Future<void> remove(String key) async {
    final file = await _file(key);
    if (await file.exists()) await file.delete();
  }
}
