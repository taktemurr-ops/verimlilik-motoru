/// Verimlilik motoru: 36 uygulamanın gerçek uygulamaları, 33 dilde metinleri
/// ve merkez görünümü. İnce depolar (uyg-*) buradan tek bir uygulama alır.
library;

export 'src/logic/doc_logic.dart';
export 'src/logic/goal_logic.dart';
export 'src/logic/otp_logic.dart';
export 'src/logic/plan_logic.dart';
export 'src/logic/text_logic.dart';
export 'src/logic/vault_logic.dart';
export 'src/registry.dart';
export 'src/tools/cv.dart' show buildCvPdf, newCv, cvHeads, cvRange, cvScripts, cvAllText, kCvLangs, kCvTemplates;
export 'src/tools/docs.dart' show RectifyJob, rectifyPage, defaultCurrency;
export 'src/tools/focus.dart' show focusStats, FocusStats;
export 'src/tools/pdf_sign.dart' show SignKind, SignMark, buildSignedPdf, strokesToJson, strokesFromJson;
export 'src/tools/lists.dart';
export 'src/tools/records.dart' show FK, FieldSpec, RecordSpec, sortRecords, matchesQuery, sumOf;
