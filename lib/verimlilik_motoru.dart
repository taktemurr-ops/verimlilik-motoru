/// Verimlilik motoru: 32 uygulamanın gerçek uygulamaları, 33 dilde metinleri
/// ve merkez görünümü. İnce depolar (uyg-*) buradan tek bir uygulama alır.
library;

export 'src/logic/doc_logic.dart';
export 'src/logic/goal_logic.dart';
export 'src/logic/plan_logic.dart';
export 'src/logic/text_logic.dart';
export 'src/logic/vault_logic.dart';
export 'src/registry.dart';
export 'src/tools/docs.dart' show RectifyJob, rectifyPage, defaultCurrency;
export 'src/tools/lists.dart';
export 'src/tools/records.dart' show FK, FieldSpec, RecordSpec, sortRecords, matchesQuery, sumOf;
