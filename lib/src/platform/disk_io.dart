import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

class Disk {
  static bool get supported => true;

  static Future<Directory> _dir(String folder) async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/$folder');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// Klasörde yeni bir dosya yolu (dosya oluşturulmaz).
  static Future<String?> newPath(String folder, String name) async {
    try {
      return '${(await _dir(folder)).path}/$name';
    } catch (_) {
      return null;
    }
  }

  static Future<bool> exists(String path) async {
    try {
      return await File(path).exists();
    } catch (_) {
      return false;
    }
  }

  static Future<void> delete(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  static Future<int> size(String path) async {
    try {
      return await File(path).length();
    } catch (_) {
      return 0;
    }
  }

  static Future<Uint8List?> read(String path) async {
    try {
      return await File(path).readAsBytes();
    } catch (_) {
      return null;
    }
  }

  static Future<String?> write(String folder, String name, Uint8List bytes) async {
    try {
      final p = '${(await _dir(folder)).path}/$name';
      await File(p).writeAsBytes(bytes, flush: true);
      return p;
    } catch (_) {
      return null;
    }
  }
}
