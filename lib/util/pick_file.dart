import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

/// A picked file: its display [name] and its [bytes].
typedef PickedFile = ({String name, Uint8List bytes});

/// Prompt for a file and read its bytes. Works on desktop and web via
/// file_selector's `XFile.readAsBytes` (no `dart:io`, so no conditional import
/// needed — unlike the write side in save_file.dart). Returns null if cancelled.
Future<PickedFile?> pickFileBytes({
  required String typeLabel,
  required List<String> extensions,
}) async {
  final file = await openFile(
    acceptedTypeGroups: [
      XTypeGroup(label: typeLabel, extensions: extensions),
    ],
  );
  if (file == null) return null; // cancelled
  return (name: file.name, bytes: await file.readAsBytes());
}
