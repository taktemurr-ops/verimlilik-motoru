/// Liste ve pano uygulamaları: kontrol/alışveriş listesi ve kanban panosu.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:studio_core/apps/apps.dart';

import '../common.dart';

typedef Js = Map<String, Object?>;

List<Js> _maps(Object? v) => [for (final e in (v as List? ?? const [])) (e as Map).cast<String, Object?>()];

// ================================================== kontrol / alışveriş

class ChecklistTool extends StatefulWidget {
  final ToolContext t;
  const ChecklistTool(this.t, {super.key});

  @override
  State<ChecklistTool> createState() => _ChecklistToolState();
}

class _ChecklistToolState extends State<ChecklistTool> {
  List<Js> _lists = [];
  String? _cur;
  final _add = TextEditingController();
  final _focus = FocusNode();
  bool _loaded = false;
  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _add.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _lists = await t.store.readList('lists');
    if (_lists.isEmpty) _lists = [{'id': newId(), 'name': L(t, 'list'), 'items': <Js>[]}];
    final cur = await t.store.read('cur');
    if (!mounted) return;
    setState(() {
      _cur = _lists.any((l) => l['id'] == cur) ? cur : _lists.first['id'] as String;
      _loaded = true;
    });
  }

  Future<void> _save() async {
    await t.store.writeList('lists', _lists);
    await t.store.write('cur', _cur ?? '');
  }

  Js get _list => _lists.firstWhere((l) => l['id'] == _cur, orElse: () => _lists.first);
  List<Js> get _items => _maps(_list['items']);
  set _items(List<Js> v) => _list['items'] = v;

  Future<void> _addItem() async {
    final raw = _add.text.trim();
    if (raw.isEmpty) return;
    // "3 elma" ya da "elma x3" biçimindeki adet algılanır.
    var qty = 1;
    var text = raw;
    final m1 = RegExp(r'^(\d{1,3})\s*[x×]?\s+(.+)$').firstMatch(raw);
    final m2 = RegExp(r'^(.+?)\s*[x×]\s*(\d{1,3})$').firstMatch(raw);
    if (m1 != null) {
      qty = int.parse(m1.group(1)!);
      text = m1.group(2)!;
    } else if (m2 != null) {
      qty = int.parse(m2.group(2)!);
      text = m2.group(1)!;
    }
    setState(() => _items = [..._items, {'id': newId(), 'text': text, 'qty': qty, 'done': false}]);
    _add.clear();
    _focus.requestFocus();
    await _save();
  }

  Future<void> _update(Js item, Js patch) async {
    setState(() => _items = [for (final i in _items) i['id'] == item['id'] ? {...i, ...patch} : i]);
    await _save();
  }

  Future<void> _listMenu() async {
    final a = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.playlist_add_rounded), title: Text(L(t, 'new_list')), onTap: () => Navigator.pop(c, 'n')),
          ListTile(leading: const Icon(Icons.edit_rounded), title: Text(L(t, 'rename')), onTap: () => Navigator.pop(c, 'r')),
          ListTile(leading: const Icon(Icons.remove_done_rounded), title: Text(L(t, 'uncheck_all')), onTap: () => Navigator.pop(c, 'u')),
          ListTile(leading: const Icon(Icons.cleaning_services_rounded), title: Text(L(t, 'remove_checked')), onTap: () => Navigator.pop(c, 'x')),
          ListTile(leading: const Icon(Icons.ios_share_rounded), title: Text(L(t, 'share')), onTap: () => Navigator.pop(c, 's')),
          if (_lists.length > 1)
            ListTile(leading: const Icon(Icons.delete_outline_rounded), title: Text(L(t, 'delete')), onTap: () => Navigator.pop(c, 'd')),
        ]),
      ),
    );
    if (!mounted || a == null) return;
    switch (a) {
      case 'n':
        final n = await askText(context, t, L(t, 'new_list'));
        if (n == null) return;
        final id = newId();
        setState(() {
          _lists.add({'id': id, 'name': n, 'items': <Js>[]});
          _cur = id;
        });
      case 'r':
        final n = await askText(context, t, L(t, 'rename'), initial: _list['name'] as String? ?? '');
        if (n != null) setState(() => _list['name'] = n);
      case 'u':
        setState(() => _items = [for (final i in _items) {...i, 'done': false}]);
      case 'x':
        setState(() => _items = _items.where((i) => i['done'] != true).toList());
      case 's':
        final txt = [
          _list['name'],
          for (final i in _items) '${i['done'] == true ? '☑' : '☐'} ${(i['qty'] as num? ?? 1) > 1 ? '${i['qty']} × ' : ''}${i['text']}',
        ].join('\n');
        await shareText(txt);
      case 'd':
        if (!await confirmDelete(context, t)) return;
        setState(() {
          _lists.removeWhere((l) => l['id'] == _cur);
          _cur = _lists.first['id'] as String;
        });
    }
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final items = _items;
    final open = items.where((i) => i['done'] != true).toList();
    final done = items.where((i) => i['done'] == true).toList();
    return ToolList(children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          for (final l in _lists)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text('${l['name']} (${_maps(l['items']).where((i) => i['done'] != true).length})'),
                selected: l['id'] == _cur,
                onSelected: (_) {
                  setState(() => _cur = l['id'] as String);
                  _save();
                },
              ),
            ),
          IconButton(onPressed: _listMenu, icon: const Icon(Icons.more_horiz_rounded)),
        ]),
      ),
      if (items.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: LinearProgressIndicator(value: done.length / items.length, minHeight: 8, borderRadius: BorderRadius.circular(8)),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _add,
              focusNode: _focus,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _addItem(),
              decoration: InputDecoration(
                hintText: L(t, 'item'),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(onPressed: _addItem, icon: const Icon(Icons.add_rounded)),
        ]),
      ),
      if (items.isEmpty) EmptyHint(L(t, 'empty_list'), icon: Icons.checklist_rounded),
      for (final i in [...open, ...done]) _tile(i),
    ]);
  }

  Widget _tile(Js i) {
    final done = i['done'] == true;
    final qty = (i['qty'] as num?)?.toInt() ?? 1;
    return Dismissible(
      key: ValueKey(i['id']),
      onDismissed: (_) {
        setState(() => _items = _items.where((x) => x['id'] != i['id']).toList());
        _save();
      },
      background: Container(color: Colors.red.withValues(alpha: 0.4)),
      child: CheckboxListTile(
        controlAffinity: ListTileControlAffinity.leading,
        value: done,
        onChanged: (v) {
          HapticFeedback.selectionClick();
          _update(i, {'done': v == true});
        },
        title: Text(i['text'] as String? ?? '',
            style: TextStyle(decoration: done ? TextDecoration.lineThrough : null, color: done ? Colors.white54 : null)),
        secondary: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: qty > 1 ? () => _update(i, {'qty': qty - 1}) : null,
            icon: const Icon(Icons.remove_rounded, size: 18),
          ),
          Text('$qty', style: const TextStyle(fontWeight: FontWeight.w800)),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => _update(i, {'qty': qty + 1}),
            icon: const Icon(Icons.add_rounded, size: 18),
          ),
        ]),
      ),
    );
  }
}

// ================================================================== kanban

class KanbanTool extends StatefulWidget {
  final ToolContext t;
  const KanbanTool(this.t, {super.key});

  @override
  State<KanbanTool> createState() => _KanbanToolState();
}

class _KanbanToolState extends State<KanbanTool> {
  List<Js> _boards = [];
  String? _cur;
  bool _loaded = false;
  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Js _newBoard(String name) => {
        'id': newId(),
        'name': name,
        'cols': [for (final c in Ls(t, 'col_defaults')) {'id': newId(), 'name': c, 'cards': <Js>[]}],
      };

  Future<void> _load() async {
    _boards = await t.store.readList('boards');
    if (_boards.isEmpty) _boards = [_newBoard(L(t, 'board'))];
    final cur = await t.store.read('cur');
    if (!mounted) return;
    setState(() {
      _cur = _boards.any((b) => b['id'] == cur) ? cur : _boards.first['id'] as String;
      _loaded = true;
    });
  }

  Future<void> _save() async {
    await t.store.writeList('boards', _boards);
    await t.store.write('cur', _cur ?? '');
  }

  Js get _board => _boards.firstWhere((b) => b['id'] == _cur, orElse: () => _boards.first);
  List<Js> get _cols => _maps(_board['cols']);
  set _cols(List<Js> v) => _board['cols'] = v;

  void _moveCard(String cardId, int toCol, [int? toIndex]) {
    final cols = _cols;
    Js? card;
    for (final c in cols) {
      final cards = _maps(c['cards']);
      final i = cards.indexWhere((x) => x['id'] == cardId);
      if (i >= 0) {
        card = cards.removeAt(i);
        c['cards'] = cards;
        break;
      }
    }
    if (card == null) return;
    final dest = _maps(cols[toCol]['cards']);
    dest.insert(toIndex == null ? dest.length : clampInt(toIndex, 0, dest.length), card);
    cols[toCol]['cards'] = dest;
    setState(() => _cols = cols);
    _save();
  }

  Future<void> _editCard(int col, [Js? card]) async {
    final c = TextEditingController(text: card?['text'] as String? ?? '');
    var color = (card?['color'] as num?)?.toInt() ?? 0;
    final res = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(L(t, 'card'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
                if (card != null) ...[
                  IconButton(
                    onPressed: col > 0 ? () => Navigator.pop(ctx, 'left') : null,
                    icon: Icon(Directionality.of(ctx) == TextDirection.rtl ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded),
                  ),
                  IconButton(
                    onPressed: col < _cols.length - 1 ? () => Navigator.pop(ctx, 'right') : null,
                    icon: Icon(Directionality.of(ctx) == TextDirection.rtl ? Icons.arrow_back_rounded : Icons.arrow_forward_rounded),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () async {
                      if (await confirmDelete(ctx, t) && ctx.mounted) Navigator.pop(ctx, 'del');
                    },
                  ),
                ],
              ]),
              AppTextField(controller: c, label: L(t, 'text'), maxLines: 6, autofocus: card == null),
              ColorRow(value: color, onChanged: (v) => set(() => color = v)),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: () => Navigator.pop(ctx, 'ok'), icon: const Icon(Icons.check_rounded), label: Text(L(t, 'save'))),
            ]),
          ),
        ),
      ),
    );
    final text = c.text.trim();
    c.dispose();
    if (res == null || !mounted) return;
    final cols = _cols;
    if (res == 'left' || res == 'right') {
      _moveCard(card!['id'] as String, col + (res == 'left' ? -1 : 1));
      return;
    }
    final cards = _maps(cols[col]['cards']);
    if (res == 'del') {
      cards.removeWhere((x) => x['id'] == card?['id']);
    } else if (text.isNotEmpty) {
      if (card == null) {
        cards.add({'id': newId(), 'text': text, 'color': color});
      } else {
        final i = cards.indexWhere((x) => x['id'] == card['id']);
        if (i >= 0) cards[i] = {...cards[i], 'text': text, 'color': color};
      }
    }
    cols[col]['cards'] = cards;
    setState(() => _cols = cols);
    await _save();
  }

  Future<void> _colMenu(int col) async {
    final a = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.edit_rounded), title: Text(L(t, 'rename')), onTap: () => Navigator.pop(c, 'r')),
          ListTile(leading: const Icon(Icons.delete_outline_rounded), title: Text(L(t, 'delete')), onTap: () => Navigator.pop(c, 'd')),
        ]),
      ),
    );
    if (!mounted || a == null) return;
    final cols = _cols;
    if (a == 'r') {
      final n = await askText(context, t, L(t, 'rename'), initial: cols[col]['name'] as String? ?? '');
      if (n == null) return;
      cols[col]['name'] = n;
    } else {
      if (!await confirmDelete(context, t)) return;
      cols.removeAt(col);
    }
    setState(() => _cols = cols);
    await _save();
  }

  Future<void> _boardMenu() async {
    final a = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.dashboard_customize_rounded), title: Text(L(t, 'new_board')), onTap: () => Navigator.pop(c, 'n')),
          ListTile(leading: const Icon(Icons.view_column_rounded), title: Text(L(t, 'new_column')), onTap: () => Navigator.pop(c, 'c')),
          ListTile(leading: const Icon(Icons.edit_rounded), title: Text(L(t, 'rename')), onTap: () => Navigator.pop(c, 'r')),
          ListTile(leading: const Icon(Icons.ios_share_rounded), title: Text(L(t, 'share')), onTap: () => Navigator.pop(c, 's')),
          if (_boards.length > 1)
            ListTile(leading: const Icon(Icons.delete_outline_rounded), title: Text(L(t, 'delete')), onTap: () => Navigator.pop(c, 'd')),
        ]),
      ),
    );
    if (!mounted || a == null) return;
    switch (a) {
      case 'n':
        final n = await askText(context, t, L(t, 'new_board'));
        if (n == null) return;
        final b = _newBoard(n);
        setState(() {
          _boards.add(b);
          _cur = b['id'] as String;
        });
      case 'c':
        final n = await askText(context, t, L(t, 'new_column'));
        if (n == null) return;
        setState(() => _cols = [..._cols, {'id': newId(), 'name': n, 'cards': <Js>[]}]);
      case 'r':
        final n = await askText(context, t, L(t, 'rename'), initial: _board['name'] as String? ?? '');
        if (n != null) setState(() => _board['name'] = n);
      case 's':
        final b = StringBuffer('${_board['name']}\n');
        for (final c in _cols) {
          b.writeln('\n## ${c['name']}');
          for (final k in _maps(c['cards'])) {
            b.writeln('- ${k['text']}');
          }
        }
        await shareText(b.toString());
      case 'd':
        if (!await confirmDelete(context, t)) return;
        setState(() {
          _boards.removeWhere((x) => x['id'] == _cur);
          _cur = _boards.first['id'] as String;
        });
    }
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final cols = _cols;
    final w = MediaQuery.sizeOf(context).width;
    final colW = w >= 900 ? 300.0 : (w * 0.82).clamp(240.0, 320.0).toDouble();
    return Column(children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(children: [
          for (final b in _boards)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(b['name'] as String? ?? ''),
                selected: b['id'] == _cur,
                onSelected: (_) {
                  setState(() => _cur = b['id'] as String);
                  _save();
                },
              ),
            ),
          IconButton(onPressed: _boardMenu, icon: const Icon(Icons.more_horiz_rounded)),
        ]),
      ),
      Expanded(
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          children: [
            for (var ci = 0; ci < cols.length; ci++) _column(ci, cols[ci], colW),
          ],
        ),
      ),
    ]);
  }

  Widget _column(int ci, Js col, double width) {
    final cards = _maps(col['cards']);
    return DragTarget<String>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) => _moveCard(d.data, ci),
      builder: (context, cand, _) => Container(
        width: width,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: cand.isEmpty ? 0.05 : 0.12),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text('${col['name']} · ${cards.length}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            IconButton(visualDensity: VisualDensity.compact, onPressed: () => _colMenu(ci), icon: const Icon(Icons.more_vert_rounded)),
          ]),
          Expanded(
            child: ListView(children: [
              for (final k in cards)
                LongPressDraggable<String>(
                  data: k['id'] as String,
                  feedback: Material(
                    color: Colors.transparent,
                    child: SizedBox(width: width - 16, child: _card(ci, k, dragging: true)),
                  ),
                  childWhenDragging: Opacity(opacity: 0.3, child: _card(ci, k)),
                  child: _card(ci, k),
                ),
              TextButton.icon(onPressed: () => _editCard(ci), icon: const Icon(Icons.add_rounded), label: Text(L(t, 'card'))),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _card(int ci, Js k, {bool dragging = false}) => Card(
        elevation: dragging ? 8 : 1,
        color: paletteAt((k['color'] as num?)?.toInt() ?? 0).withValues(alpha: 0.3),
        child: InkWell(
          onTap: dragging ? null : () => _editCard(ci, k),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(k['text'] as String? ?? '', style: const TextStyle(fontSize: 15)),
          ),
        ),
      );
}
