import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

Future<void> writeFont(String id, Uint8List bytes) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('fontData_$id', base64Encode(bytes));
}

Future<Uint8List> readFont(String id) async {
  final prefs = await SharedPreferences.getInstance();
  final value = prefs.getString('fontData_$id');
  if (value == null) throw const FormatException('字体文件不存在');
  return base64Decode(value);
}
