/// Cross-checks this app against the Python Fantasian-Save-Transfer tool.
///
/// Skipped unless `FANTASIAN_REF_TOOL` points at its `fantasian.py`:
///
/// ```sh
/// FANTASIAN_REF_TOOL=/path/to/fantasian.py flutter test test/interop
/// ```
library;

import 'dart:io';

import 'package:fantasian_sge/src/core/arcade_database.dart';
import 'package:fantasian_sge/src/core/json_reading.dart';
import 'package:fantasian_sge/src/core/save_loader.dart';
import 'package:fantasian_sge/src/core/save_models.dart';
import 'package:fantasian_sge/src/core/save_transfer.dart';
import 'package:fantasian_sge/src/core/steam_root.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/fixtures.dart';

void main() {
  final String? tool = Platform.environment['FANTASIAN_REF_TOOL'];
  final String? skip = tool == null ? 'FANTASIAN_REF_TOOL is not set' : null;

  late Directory temp;
  setUp(() async => temp = await Directory.systemTemp.createTemp('fsge_interop_'));
  tearDown(() async => temp.delete(recursive: true));

  /// Runs the reference tool with [args] and returns its stdout.
  Future<String> runTool(List<String> args) async {
    final ProcessResult result = await Process.run('python3', <String>['-I', tool!, ...args]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    return '${result.stdout}';
  }

  test('a root.json written here is read by the reference tool', () async {
    final Directory folder = Directory(p.join(temp.path, 'FANTASIAN'));
    await writeArcadeDatabase(folder);
    final LoadedSave save = await SaveLoader().loadFolder(folder.path);
    final SteamBuildResult built = SaveTransfer().buildSteamRoot(
      save,
      save.records.map((SaveRecord r) => r.path).toSet(),
    );
    final String out = p.join(temp.path, 'root.json');
    await File(out).writeAsString(built.json);

    final String listing = await runTool(<String>['slots', out]);
    for (final String name in <String>['GameData0', 'GameData1', 'GameData2', 'GameData10']) {
      expect(listing, contains(name));
    }
    expect(listing, contains('35,868'));
  }, skip: skip);

  test('a root.json written by the reference tool is read here, identically', () async {
    final Directory folder = Directory(p.join(temp.path, 'FANTASIAN'));
    await writeArcadeDatabase(folder);
    final String out = p.join(temp.path, 'ref_root.json');
    await runTool(<String>['to-steam', folder.path, '-o', out]);

    final LoadedSave fromRef = await SaveLoader().loadSteamFile(out);
    final LoadedSave original = await SaveLoader().loadFolder(folder.path);
    expect(fromRef.origin, SaveOrigin.neoDimension);
    final Map<String, String> want = <String, String>{
      for (final SaveRecord r in original.records) r.path: r.plaintext,
    };
    final Map<String, String> got = <String, String>{
      for (final SaveRecord r in fromRef.records) r.path: r.plaintext,
    };
    expect(got, want);

    // Our build of the same slots must encrypt to the very same records.
    final String ours = SaveTransfer().buildSteamRoot(original, want.keys.toSet()).json;
    // Same order, same ciphertext, byte for byte.
    String innerRecords(String rootJson) => requireString(
      decodeJsonObject(rootJson, what: 'root')['dataString'],
      what: 'dataString',
    );
    expect(innerRecords(ours), innerRecords(await File(out).readAsString()));
  }, skip: skip);

  test('a database this app wrote is read by the reference tool', () async {
    final Directory folder = Directory(p.join(temp.path, 'FANTASIAN'));
    final String db = await writeArcadeDatabase(folder);
    await ArcadeDatabase.writeRecords(db, arcadeSlots.sublist(0, 2));
    final String listing = await runTool(<String>['slots', folder.path]);
    expect(listing, contains('2 save slot'));
  }, skip: skip);
}
