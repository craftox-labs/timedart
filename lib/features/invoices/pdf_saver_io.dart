import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Native save. Desktop → a save-as dialog. Mobile (Android/iOS) → the OS
/// share sheet, because file_selector's getSaveLocation is unimplemented on
/// Android; sharing is also how a phone user reads/sends the invoice.
Future<String?> savePdf(Uint8List bytes, String suggestedName) async {
  if (Platform.isAndroid || Platform.isIOS) {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$suggestedName');
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    return suggestedName; // non-null → caller won't treat it as a cancel
  }

  // Desktop: prompt for a location and write the file.
  final location = await getSaveLocation(
    suggestedName: suggestedName,
    acceptedTypeGroups: const [
      XTypeGroup(label: 'PDF', extensions: ['pdf']),
    ],
  );
  if (location == null) return null; // cancelled
  await File(location.path).writeAsBytes(bytes);
  return location.path;
}
