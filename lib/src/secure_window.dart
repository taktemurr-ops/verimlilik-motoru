/// Hassas ekranlar (şifre kasası) için pencere koruması.
///
/// Android'de merkez uygulamanın MainActivity'si `gs100/secure_window`
/// kanalında FLAG_SECURE'u açıp kapatır: ekran görüntüsü, ekran kaydı ve
/// "son uygulamalar" önizlemesi boş görünür. Kanal yoksa (testler, web,
/// iOS) sessizce hiçbir şey yapmaz; iOS'ta uygulama değiştirici önizlemesi
/// ekranın kendi örtüsüyle gizlenir (bkz. [SecureCurtain]).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('gs100/secure_window');
int _holders = 0;

/// Bir hassas ekran açıldı/kapandı. İç içe ekranlar için sayaç tutulur.
Future<void> secureWindow(bool on) async {
  _holders = on ? _holders + 1 : (_holders > 0 ? _holders - 1 : 0);
  if (kIsWeb) return;
  try {
    await _channel.invokeMethod<bool>('set', _holders > 0);
  } catch (_) {
    // Kanal tanımlı değil (test / bağımsız derleme): yok say.
  }
}

/// Uygulama ön planda değilken (uygulama değiştirici, bildirim perdesi)
/// içeriği örten katman.
class SecureCurtain extends StatefulWidget {
  final Widget child;
  const SecureCurtain({super.key, required this.child});

  @override
  State<SecureCurtain> createState() => _SecureCurtainState();
}

class _SecureCurtainState extends State<SecureCurtain> with WidgetsBindingObserver {
  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    secureWindow(true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    secureWindow(false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final hide = state != AppLifecycleState.resumed;
    if (hide != _hidden && mounted) setState(() => _hidden = hide);
  }

  @override
  Widget build(BuildContext context) => Stack(children: [
        widget.child,
        if (_hidden)
          Positioned.fill(
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: const Center(child: Icon(Icons.lock_rounded, size: 64)),
            ),
          ),
      ]);
}
