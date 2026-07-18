import 'dart:io';

import 'package:timedart/cli/cli.dart';

/// The timedart companion CLI entry point (PRD #270). A NON-Flutter Dart
/// entrypoint — compiled with `dart compile exe` into a single portable binary
/// — so it must transitively import only pure Dart (no Flutter platform
/// channels). All work is delegated to [runTimedartCli]; this shim only turns
/// its returned exit code into the process exit status.
Future<void> main(List<String> args) async {
  final code = await runTimedartCli(args);
  exit(code);
}
