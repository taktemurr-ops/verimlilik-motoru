/// Bildirimler: mobilde flutter_local_notifications, web'de yalnızca
/// uygulama içi uyarı.
library;

export 'notify_stub.dart' if (dart.library.io) 'notify_io.dart';
