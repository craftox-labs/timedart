import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Web save: hands [bytes] to the browser as a download.
///
/// There is no cancel affordance on web, so this always returns the filename.
/// [typeLabel] and [extensions] are unused here (the browser names the file);
/// they stay in the signature for parity with the native impl.
Future<String?> saveBytes(
  Uint8List bytes, {
  required String suggestedName,
  required String typeLabel,
  required List<String> extensions,
  required String mimeType,
}) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  web.HTMLAnchorElement()
    ..href = url
    ..download = suggestedName
    ..click();
  web.URL.revokeObjectURL(url);
  return suggestedName;
}
