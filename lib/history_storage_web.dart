import 'package:shared_preferences/shared_preferences.dart';

import 'history_storage.dart';

class LocalHistoryStorage implements HistoryStorage {
  @override
  Future<String?> read(String key) async =>
      (await SharedPreferences.getInstance()).getString('history_$key');

  @override
  Future<void> write(String key, String value) async {
    final saved = await (await SharedPreferences.getInstance()).setString(
      'history_$key',
      value,
    );
    if (!saved) throw StateError('本地存储空间不足');
  }

  @override
  Future<void> remove(String key) async {
    await (await SharedPreferences.getInstance()).remove('history_$key');
  }
}
