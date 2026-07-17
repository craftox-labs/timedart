import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:timedart/data/legacy_db_migration_io.dart';

// Coverage for the pre-1.0 database move: from the bundle-id folder under the
// legacy name (time_tracker.sqlite) to a plainly-named `timedart` folder as
// timedart.sqlite. Exercises the directory-injected core (moveLegacyDatabaseFile)
// against real temp directories, so no path_provider channel is needed.

void main() {
  late Directory root;
  late Directory oldDir;
  late Directory newDir;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('timedart_legacy_db');
    oldDir = await Directory('${root.path}/dev.craftox.timedart').create();
    newDir = Directory('${root.path}/timedart');
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  File oldFile(String name, [String suffix = '']) =>
      File('${oldDir.path}${Platform.pathSeparator}$name$suffix');
  File newFile([String suffix = '']) =>
      File('${newDir.path}${Platform.pathSeparator}timedart.sqlite$suffix');

  test('moves the legacy file into the new folder, preserving contents',
      () async {
    await oldFile('time_tracker.sqlite').writeAsString('DB-BYTES');

    await moveLegacyDatabaseFile(oldDir.path, newDir.path);

    expect(await oldFile('time_tracker.sqlite').exists(), isFalse);
    expect(await newFile().exists(), isTrue);
    expect(await newFile().readAsString(), 'DB-BYTES');
  });

  test('moves the -wal/-shm sidecars alongside the main file', () async {
    await oldFile('time_tracker.sqlite').writeAsString('main');
    await oldFile('time_tracker.sqlite', '-wal').writeAsString('wal');
    await oldFile('time_tracker.sqlite', '-shm').writeAsString('shm');

    await moveLegacyDatabaseFile(oldDir.path, newDir.path);

    expect(await newFile('-wal').readAsString(), 'wal');
    expect(await newFile('-shm').readAsString(), 'shm');
    expect(await oldFile('time_tracker.sqlite', '-wal').exists(), isFalse);
  });

  test('also relocates an already-renamed timedart.sqlite', () async {
    await oldFile('timedart.sqlite').writeAsString('already-renamed');

    await moveLegacyDatabaseFile(oldDir.path, newDir.path);

    expect(await newFile().readAsString(), 'already-renamed');
    expect(await oldFile('timedart.sqlite').exists(), isFalse);
  });

  test('coinciding directories degrade to an in-place rename (defensive)',
      () async {
    // moveLegacyDatabaseFile must never destroy data if handed the same path
    // for both directories.
    await oldFile('time_tracker.sqlite').writeAsString('DB-BYTES');

    await moveLegacyDatabaseFile(oldDir.path, oldDir.path);

    expect(
      await File('${oldDir.path}/timedart.sqlite').readAsString(),
      'DB-BYTES',
    );
    expect(await oldFile('time_tracker.sqlite').exists(), isFalse);
  });

  test('is a no-op when there is no legacy file (fresh install)', () async {
    await moveLegacyDatabaseFile(oldDir.path, newDir.path);
    expect(await newFile().exists(), isFalse);
  });

  test('does not clobber an existing timedart.sqlite in the new folder',
      () async {
    await newDir.create(recursive: true);
    await oldFile('time_tracker.sqlite').writeAsString('OLD');
    await newFile().writeAsString('CURRENT');

    await moveLegacyDatabaseFile(oldDir.path, newDir.path);

    expect(await newFile().readAsString(), 'CURRENT');
  });

  test('is idempotent — safe to run twice', () async {
    await oldFile('time_tracker.sqlite').writeAsString('DB-BYTES');

    await moveLegacyDatabaseFile(oldDir.path, newDir.path);
    await moveLegacyDatabaseFile(oldDir.path, newDir.path);

    expect(await newFile().readAsString(), 'DB-BYTES');
    expect(await oldFile('time_tracker.sqlite').exists(), isFalse);
  });
}
