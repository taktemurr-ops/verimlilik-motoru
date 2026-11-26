/// Ses uygulamaları: ses kaydedici ve sesten yazıya not.
library;

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:studio_core/apps/apps.dart';

import '../common.dart';
import '../platform/disk.dart';

// ============================================================ ses kaydedici

class RecorderTool extends StatefulWidget {
  final ToolContext t;
  const RecorderTool(this.t, {super.key});

  @override
  State<RecorderTool> createState() => _RecorderToolState();
}

class _RecorderToolState extends State<RecorderTool> {
  final AudioRecorder _rec = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  List<Map<String, Object?>> _items = [];
  String? _path;
  bool _paused = false;
  final Stopwatch _sw = Stopwatch();
  Timer? _tick;
  double _level = 0;
  StreamSubscription<Amplitude>? _amp;
  String? _playing;
  Duration _pos = Duration.zero, _dur = Duration.zero;
  final List<StreamSubscription<Object?>> _subs = [];
  bool _loaded = false;
  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    if (!Disk.supported) return;
    _load();
    _subs.add(_player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _pos = p);
    }));
    _subs.add(_player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _dur = d);
    }));
    _subs.add(_player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = null);
    }));
  }

  Future<void> _load() async {
    final l = await t.store.readList('recs');
    final ok = <Map<String, Object?>>[];
    for (final r in l) {
      if (await Disk.exists(r['path'] as String? ?? '')) ok.add(r);
    }
    if (!mounted) return;
    setState(() {
      _items = ok;
      _loaded = true;
    });
  }

  Future<void> _save() => t.store.writeList('recs', _items);

  Future<void> _start() async {
    if (!await rationaleOnce(context, t, 'mic', Icons.mic_rounded)) return;
    try {
      if (!await _rec.hasPermission()) {
        if (mounted) showPermissionDenied(context, t.lang);
        return;
      }
      final now = DateTime.now();
      final p = await Disk.newPath('recordings', 'rec_${now.millisecondsSinceEpoch}.m4a');
      if (p == null) return;
      await _player.stop();
      await _rec.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100), path: p);
      _amp = _rec.onAmplitudeChanged(const Duration(milliseconds: 120)).listen((a) {
        if (mounted) setState(() => _level = ((a.current + 50) / 50).clamp(0.0, 1.0).toDouble());
      });
      _sw
        ..reset()
        ..start();
      _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (mounted) setState(() {});
      });
      setState(() {
        _path = p;
        _paused = false;
        _playing = null;
      });
    } catch (_) {
      if (mounted) toast(context, t.tx('not_available'));
    }
  }

  Future<void> _pauseResume() async {
    if (_paused) {
      await _rec.resume();
      _sw.start();
    } else {
      await _rec.pause();
      _sw.stop();
    }
    setState(() => _paused = !_paused);
  }

  Future<void> _stop() async {
    final p = await _rec.stop();
    _sw.stop();
    _tick?.cancel();
    await _amp?.cancel();
    final path = p ?? _path;
    final ms = _sw.elapsedMilliseconds;
    setState(() {
      _path = null;
      _level = 0;
    });
    if (path == null || !await Disk.exists(path)) return;
    final now = DateTime.now();
    if (!mounted) return;
    setState(() => _items.insert(0, {
          'id': newId(),
          'name': '${L(t, 'recording')} ${fmtDateTime(context, now)}',
          'path': path,
          'ms': ms,
          'at': now.millisecondsSinceEpoch,
        }));
    await _save();
  }

  Future<void> _play(Map<String, Object?> r) async {
    final id = r['id'] as String;
    if (_playing == id) {
      await _player.pause();
      setState(() => _playing = null);
      return;
    }
    await _player.stop();
    await _player.play(DeviceFileSource(r['path'] as String));
    setState(() {
      _playing = id;
      _pos = Duration.zero;
    });
  }

  Future<void> _menu(Map<String, Object?> r) async {
    final a = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.edit_rounded), title: Text(L(t, 'rename')), onTap: () => Navigator.pop(c, 'r')),
          ListTile(leading: const Icon(Icons.ios_share_rounded), title: Text(L(t, 'share')), onTap: () => Navigator.pop(c, 's')),
          ListTile(leading: const Icon(Icons.delete_outline_rounded), title: Text(L(t, 'delete')), onTap: () => Navigator.pop(c, 'd')),
        ]),
      ),
    );
    if (!mounted || a == null) return;
    if (a == 'r') {
      final n = await askText(context, t, L(t, 'rename'), initial: r['name'] as String? ?? '');
      if (n != null) setState(() => r['name'] = n);
    } else if (a == 's') {
      await sharePath(r['path'] as String, 'audio/mp4');
    } else if (a == 'd') {
      if (!await confirmDelete(context, t)) return;
      if (_playing == r['id']) await _player.stop();
      await Disk.delete(r['path'] as String);
      setState(() => _items.remove(r));
    }
    await _save();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _amp?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    if (_path != null) _rec.stop();
    _rec.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!Disk.supported) return ToolList(children: [notAvailable(t)]);
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final rec = _path != null;
    return ToolList(children: [
      AppPanel(
        child: Column(children: [
          Text(fmtDuration(_sw.elapsed),
              style: TextStyle(fontSize: 56, fontWeight: FontWeight.w900, color: AppLook.of(context).number)),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: rec && !_paused ? _level : 0, minHeight: 10, borderRadius: BorderRadius.circular(8)),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (rec)
              IconButton.filledTonal(
                iconSize: 32,
                onPressed: _pauseResume,
                icon: Icon(_paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
              ),
            const SizedBox(width: 16),
            FloatingActionButton.large(
              heroTag: null,
              backgroundColor: rec ? Colors.redAccent : null,
              onPressed: rec ? _stop : _start,
              child: Icon(rec ? Icons.stop_rounded : Icons.mic_rounded, size: 44),
            ),
          ]),
          const SizedBox(height: 8),
          Text(rec ? L(t, 'recording') : L(t, 'record'), style: const TextStyle(color: Colors.white70)),
        ]),
      ),
      AppInfoCard(L(t, 'rec_foreground'), icon: Icons.info_outline_rounded),
      SectionBar(L(t, 'recordings'), icon: Icons.library_music_rounded),
      if (_items.isEmpty) EmptyHint(L(t, 'empty_list'), icon: Icons.mic_none_rounded),
      for (final r in _items)
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(children: [
            ListTile(
              leading: IconButton(
                onPressed: rec ? null : () => _play(r),
                icon: Icon(_playing == r['id'] ? Icons.pause_circle_rounded : Icons.play_circle_rounded, size: 36),
              ),
              title: Text(r['name'] as String? ?? ''),
              subtitle: Text(fmtDuration(Duration(milliseconds: (r['ms'] as num?)?.toInt() ?? 0))),
              trailing: IconButton(onPressed: () => _menu(r), icon: const Icon(Icons.more_vert_rounded)),
            ),
            if (_playing == r['id'] && _dur.inMilliseconds > 0)
              Slider(
                value: _pos.inMilliseconds.clamp(0, _dur.inMilliseconds).toDouble(),
                max: _dur.inMilliseconds.toDouble(),
                onChanged: (v) => _player.seek(Duration(milliseconds: v.round())),
              ),
          ]),
        ),
    ]);
  }
}

// =========================================================== sesten yazıya

class SpeechNoteTool extends StatefulWidget {
  final ToolContext t;
  const SpeechNoteTool(this.t, {super.key});

  @override
  State<SpeechNoteTool> createState() => _SpeechNoteToolState();
}

class _SpeechNoteToolState extends State<SpeechNoteTool> {
  final SpeechToText _stt = SpeechToText();
  final _text = TextEditingController();
  bool? _ready;
  bool _listening = false;
  bool _onDevice = true;
  String _partial = '';
  String? _locale;
  List<LocaleName> _locales = [];
  List<Map<String, Object?>> _notes = [];
  String? _editing;
  String? _error;
  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _notes = await t.store.readList('notes');
    _onDevice = await t.store.readBool('on_device', true);
    _locale = await t.store.read('locale');
    if (mounted) setState(() {});
  }

  Future<void> _saveNotes() => t.store.writeList('notes', _notes);

  Future<bool> _init() async {
    if (_ready == true) return true;
    if (!await rationaleOnce(context, t, 'mic', Icons.mic_rounded)) return false;
    try {
      final ok = await _stt.initialize(
        onError: (e) {
          if (!mounted) return;
          setState(() {
            _listening = false;
            _error = e.errorMsg;
          });
        },
        onStatus: (s) {
          if (!mounted) return;
          if (s == 'done' || s == 'notListening') setState(() => _listening = false);
        },
      );
      if (ok) {
        _locales = await _stt.locales();
        if (_locale == null || !_locales.any((l) => l.localeId == _locale)) {
          final mine = _locales.where((l) => l.localeId.toLowerCase().startsWith(t.lang == 'nb' ? 'nb' : t.lang)).firstOrNull;
          _locale = mine?.localeId ?? (await _stt.systemLocale())?.localeId;
        }
      }
      if (mounted) setState(() => _ready = ok);
      return ok;
    } catch (_) {
      if (mounted) setState(() => _ready = false);
      return false;
    }
  }

  Future<void> _listen() async {
    if (_listening) {
      await _stt.stop();
      setState(() => _listening = false);
      return;
    }
    if (!await _init()) return;
    setState(() {
      _listening = true;
      _partial = '';
      _error = null;
    });
    await _stt.listen(
      localeId: _locale,
      listenFor: const Duration(minutes: 5),
      pauseFor: const Duration(seconds: 6),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        onDevice: _onDevice,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
      ),
      onResult: _onResult,
    );
  }

  void _onResult(SpeechRecognitionResult r) {
    if (!mounted) return;
    if (r.finalResult) {
      final add = r.recognizedWords.trim();
      if (add.isNotEmpty) {
        final cur = _text.text.trimRight();
        _text.text = cur.isEmpty ? add : '$cur $add';
      }
      setState(() => _partial = '');
    } else {
      setState(() => _partial = r.recognizedWords);
    }
  }

  Future<void> _saveCurrent() async {
    final v = _text.text.trim();
    if (v.isEmpty) return;
    setState(() {
      if (_editing != null) {
        final i = _notes.indexWhere((n) => n['id'] == _editing);
        if (i >= 0) _notes[i] = {..._notes[i], 'text': v, 'at': DateTime.now().millisecondsSinceEpoch};
      } else {
        _notes.insert(0, {'id': newId(), 'text': v, 'at': DateTime.now().millisecondsSinceEpoch});
      }
      _editing = null;
      _text.clear();
    });
    await _saveNotes();
  }

  @override
  void dispose() {
    _stt.cancel();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_ready == false) {
      return ToolList(children: [notAvailable(t), AppInfoCard(L(t, 'stt_note'))]);
    }
    return ToolList(children: [
      AppPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppTextField(controller: _text, label: L(t, 'note'), maxLines: 12, minLines: 5),
          if (_partial.isNotEmpty) Text(_partial, style: const TextStyle(color: Colors.white60, fontStyle: FontStyle.italic)),
          if (_error != null) Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            FloatingActionButton.large(
              heroTag: null,
              backgroundColor: _listening ? Colors.redAccent : null,
              onPressed: _listen,
              child: Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded, size: 44),
            ),
          ]),
          const SizedBox(height: 6),
          Text(_listening ? L(t, 'listening') : L(t, 'tap_to_speak'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
          // Dar ekranda ve büyük yazıda düğmeler alt satıra geçer.
          Wrap(alignment: WrapAlignment.spaceBetween, spacing: 8, runSpacing: 6, children: [
            TextButton.icon(onPressed: _text.text.isEmpty ? null : () => copyText(context, t, _text.text), icon: const Icon(Icons.copy_rounded), label: Text(t.tx('copied'))),
            FilledButton.icon(onPressed: _saveCurrent, icon: const Icon(Icons.save_rounded), label: Text(L(t, 'save'))),
          ]),
        ]),
      ),
      AppPanel(
        child: Column(children: [
          if (_locales.isNotEmpty)
            Pick<String>(
              label: L(t, 'language'),
              values: _locales.map((l) => l.localeId).toList(),
              text: (id) => _locales.firstWhere((l) => l.localeId == id).name,
              value: _locale ?? _locales.first.localeId,
              onChanged: (v) {
                setState(() => _locale = v);
                t.store.write('locale', v);
              },
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(L(t, 'on_device_only')),
            value: _onDevice,
            onChanged: (v) {
              setState(() => _onDevice = v);
              t.store.writeBool('on_device', v);
            },
          ),
          Text(L(t, 'stt_note'), style: const TextStyle(color: Colors.white60, fontSize: 13)),
        ]),
      ),
      SectionBar(L(t, 'notes'), icon: Icons.notes_rounded),
      if (_notes.isEmpty) EmptyHint(L(t, 'empty_list'), icon: Icons.record_voice_over_rounded),
      for (final n in _notes)
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            title: Text(n['text'] as String? ?? '', maxLines: 4, overflow: TextOverflow.ellipsis),
            subtitle: Text(fmtDateTime(context, DateTime.fromMillisecondsSinceEpoch((n['at'] as num?)?.toInt() ?? 0)),
                style: const TextStyle(fontSize: 12, color: Colors.white54)),
            onTap: () => setState(() {
              _editing = n['id'] as String;
              _text.text = n['text'] as String? ?? '';
            }),
            trailing: PopupMenuButton<String>(
              onSelected: (a) async {
                if (a == 's') await shareText(n['text'] as String? ?? '');
                if (a == 'd' && mounted && await confirmDelete(context, t)) {
                  setState(() => _notes.remove(n));
                  await _saveNotes();
                }
              },
              itemBuilder: (c) => [
                PopupMenuItem(value: 's', child: Text(L(t, 'share'))),
                PopupMenuItem(value: 'd', child: Text(L(t, 'delete'))),
              ],
            ),
          ),
        ),
    ]);
  }
}
