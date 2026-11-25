/// Kayıt listesi motorunu kullanan uygulamaların tanımları.
library;

import 'package:flutter/material.dart';

import 'records.dart';

const kNotesSpec = RecordSpec(
  fields: [
    FieldSpec('title', 'title', FK.text),
    FieldSpec('body', 'note', FK.longText),
    FieldSpec('color', 'color', FK.color),
  ],
  titleKey: 'title',
  subtitleKeys: ['body'],
  pinnable: true,
  colorKey: 'color',
  itemLabel: 'note',
  icon: Icons.sticky_note_2_rounded,
);

const kTodoSpec = RecordSpec(
  fields: [
    FieldSpec('task', 'task', FK.text),
    FieldSpec('due', 'due', FK.date),
    FieldSpec('prio', 'priority', FK.choice, choices: 'prio_levels'),
    FieldSpec('done', 'done', FK.check),
    FieldSpec('note', 'note', FK.longText),
  ],
  titleKey: 'task',
  subtitleKeys: ['due', 'prio', 'note'],
  doneKey: 'done',
  dateKey: 'due',
  dateIsDue: true,
  pinnable: true,
  filterKey: 'prio',
  itemLabel: 'task',
  icon: Icons.task_alt_rounded,
);

const kHomeworkSpec = RecordSpec(
  fields: [
    FieldSpec('task', 'assignment', FK.text),
    FieldSpec('subject', 'subject', FK.text),
    FieldSpec('due', 'due', FK.date),
    FieldSpec('prio', 'priority', FK.choice, choices: 'prio_levels'),
    FieldSpec('done', 'done', FK.check),
    FieldSpec('note', 'note', FK.longText),
  ],
  titleKey: 'task',
  subtitleKeys: ['subject', 'due', 'prio'],
  doneKey: 'done',
  dateKey: 'due',
  dateIsDue: true,
  itemLabel: 'assignment',
  icon: Icons.menu_book_rounded,
);

const kReadingSpec = RecordSpec(
  fields: [
    FieldSpec('title', 'title', FK.text),
    FieldSpec('author', 'author', FK.text),
    FieldSpec('status', 'status', FK.choice, choices: 'read_opts'),
    FieldSpec('pages', 'pages', FK.number),
    FieldSpec('rating', 'rating', FK.rating),
    FieldSpec('note', 'note', FK.longText),
  ],
  titleKey: 'title',
  subtitleKeys: ['author', 'status', 'rating'],
  filterKey: 'status',
  itemLabel: 'book',
  icon: Icons.auto_stories_rounded,
);

const kWatchSpec = RecordSpec(
  fields: [
    FieldSpec('title', 'title', FK.text),
    FieldSpec('kind', 'kind', FK.choice, choices: 'kind_opts'),
    FieldSpec('status', 'status', FK.choice, choices: 'watch_opts'),
    FieldSpec('season', 'season', FK.number),
    FieldSpec('episode', 'episode', FK.number),
    FieldSpec('rating', 'rating', FK.rating),
    FieldSpec('note', 'note', FK.longText),
  ],
  titleKey: 'title',
  subtitleKeys: ['kind', 'status', 'season', 'episode', 'rating'],
  filterKey: 'status',
  incKey: 'episode',
  itemLabel: 'title',
  icon: Icons.movie_rounded,
);

const kReceiptSpec = RecordSpec(
  fields: [
    FieldSpec('shop', 'shop', FK.text),
    FieldSpec('date', 'date', FK.date),
    FieldSpec('amount', 'amount', FK.money),
    FieldSpec('cat', 'category', FK.choice, choices: 'rcat_opts'),
    FieldSpec('note', 'note', FK.longText),
  ],
  titleKey: 'shop',
  subtitleKeys: ['date', 'cat', 'note'],
  dateKey: 'date',
  sumKey: 'amount',
  monthFilter: true,
  filterKey: 'cat',
  info: 'receipt_note',
  itemLabel: 'receipt',
  icon: Icons.receipt_rounded,
);

const kInventorySpec = RecordSpec(
  fields: [
    FieldSpec('name', 'name', FK.text),
    FieldSpec('loc', 'location', FK.text),
    FieldSpec('qty', 'qty', FK.number),
    FieldSpec('code', 'code', FK.text),
    FieldSpec('note', 'note', FK.longText),
  ],
  titleKey: 'name',
  subtitleKeys: ['loc', 'qty', 'code'],
  codeKey: 'code',
  itemLabel: 'item',
  icon: Icons.inventory_2_rounded,
);
