/// Web: sistem bildirimi yok; araçlar uygulama içinde uyarır.
library;

class Notify {
  static bool get supported => false;
  static Future<void> init() async {}
  static Future<bool> requestPermission() async => false;
  static Future<void> schedule(int id, String title, String body, DateTime when) async {}
  static Future<void> cancel(int id) async {}
}
