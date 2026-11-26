/// Android odak kilidi köprüsü (verimlilik_motoru/focus → FocusService).
/// Diğer platformlarda yalnızca uygulama içi odak sayacı vardır.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class FocusStatus {
  final bool usage;
  final bool overlay;
  final bool running;
  final int endsAt;
  const FocusStatus({this.usage = false, this.overlay = false, this.running = false, this.endsAt = 0});
}

class FocusApp {
  final String pkg;
  final String label;
  final int ms;
  const FocusApp(this.pkg, this.label, [this.ms = 0]);
}

class FocusNative {
  static const _ch = MethodChannel('verimlilik_motoru/focus');

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<FocusStatus> status() async {
    if (!supported) return const FocusStatus();
    try {
      final m = await _ch.invokeMethod<Map<Object?, Object?>>('status');
      return FocusStatus(
        usage: m?['usage'] == true,
        overlay: m?['overlay'] == true,
        running: m?['running'] == true,
        endsAt: (m?['endsAt'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return const FocusStatus();
    }
  }

  static Future<void> openUsage() async {
    if (!supported) return;
    try {
      await _ch.invokeMethod<bool>('openUsage');
    } catch (_) {}
  }

  static Future<void> openOverlay() async {
    if (!supported) return;
    try {
      await _ch.invokeMethod<bool>('openOverlay');
    } catch (_) {}
  }

  static List<FocusApp> _apps(List<Object?>? l) => [
        for (final o in l ?? const [])
          if (o is Map) FocusApp('${o['pkg']}', '${o['label']}', (o['ms'] as num?)?.toInt() ?? 0),
      ];

  /// Başlatıcıdaki uygulamalar (bu uygulama hariç).
  static Future<List<FocusApp>> apps() async {
    if (!supported) return const [];
    try {
      return _apps(await _ch.invokeMethod<List<Object?>>('apps'));
    } catch (_) {
      return const [];
    }
  }

  /// Bugünkü ön plan süreleri (en çok kullanılan 25 uygulama).
  static Future<List<FocusApp>> usageToday() async {
    if (!supported) return const [];
    try {
      return _apps(await _ch.invokeMethod<List<Object?>>('usage'));
    } catch (_) {
      return const [];
    }
  }

  static Future<bool> start({
    required List<String> packages,
    required int endsAt,
    required Map<String, String> texts,
  }) async {
    if (!supported) return false;
    try {
      return await _ch.invokeMethod<bool>('start', {'packages': packages, 'endsAt': endsAt, ...texts}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> stop() async {
    if (!supported) return;
    try {
      await _ch.invokeMethod<bool>('stop');
    } catch (_) {}
  }
}
