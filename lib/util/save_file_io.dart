import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

/// Native save: prompts for a location and writes [bytes] there.
///
/// Returns the saved path, or null if the user cancelled the dialog. [mimeType]
/// is unused natively (the file dialog filters by extension) but kept in the
/// signature so web and desktop callers stay identical.
Future<String?> saveBytes(
  Uint8List bytes, {
  required String suggestedName,
  required String typeLabel,
  required List<String> extensions,
  required String mimeType,
}) async {
  final location = await getSaveLocation(
    suggestedName: suggestedName,
    acceptedTypeGroups: [
      XTypeGroup(label: typeLabel, extensions: extensions),
    ],
  );
  if (location == null) return null; // cancelled
  await File(location.path).writeAsBytes(bytes);
  return location.path;
}
