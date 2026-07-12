// Platform-agnostic "save bytes to a file the user chooses".
//
// Desktop writes to a native save dialog; web triggers a browser download. The
// conditional export keeps callers free of `dart:io` (uncompilable on web).
// Generalises the invoice-only pdf_saver so data export/import can reuse it.
export 'save_file_io.dart' if (dart.library.js_interop) 'save_file_web.dart';
