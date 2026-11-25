import 'dart:typed_data';

class Disk {
  static bool get supported => false;
  static Future<String?> newPath(String folder, String name) async => null;
  static Future<bool> exists(String path) async => false;
  static Future<void> delete(String path) async {}
  static Future<int> size(String path) async => 0;
  static Future<Uint8List?> read(String path) async => null;
  static Future<String?> write(String folder, String name, Uint8List bytes) async => null;
}
