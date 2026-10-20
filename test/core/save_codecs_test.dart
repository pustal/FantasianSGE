import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fantasian_sge/src/core/arcade_database.dart';
import 'package:fantasian_sge/src/core/arcade_payload.dart';
import 'package:fantasian_sge/src/core/json_reading.dart';
import 'package:fantasian_sge/src/core/save_exception.dart';
import 'package:fantasian_sge/src/core/save_loader.dart';
import 'package:fantasian_sge/src/core/save_models.dart';
import 'package:fantasian_sge/src/core/save_transfer.dart';
import 'package:fantasian_sge/src/core/steam_root.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../support/fixtures.dart';

void main() {
  late Directory temp;

  setUp(() async => temp = await Directory.systemTemp.createTemp('fsge_test_'));
  tearDown(() async => temp.delete(recursive: true));

  group('SaveRecord', () {
    test('names slots the way the game does', () {
      expect(arcadeSlots[1].gameLabel, 'Autosave');
      expect(arcadeSlots[0].gameLabel, 'Slot 1');
      expect(arcadeSlots[3].fileLabel, 'GameData10');
    });

    test('summarises play time, gil and map', () {
      final SlotSummary summary = arcadeSlots[1].summarise();
      expect(summary.problem, isNull);
      expect(summary.playTime, const Duration(seconds: 60000));
      expect(summary.money, 35868);
      expect(summary.mapId, 'CityVibra');
      expect(summary.savedAt, '2026/08/19 09:44:41');
    });

    test('reports an unreadable slot instead of throwing', () {
      const SaveRecord broken = SaveRecord(path: 'Data/GameData3.json', plaintext: 'nope');
      expect(broken.summarise().problem, isNotNull);
    });
  });

  group('ArcadePayload', () {
    test('round-trips records and keeps their order', () {
      final List<SaveRecord> back = ArcadePayload.decode(ArcadePayload.encode(arcadeSlots));
      expect(back.map((SaveRecord r) => r.path), arcadeSlots.map((SaveRecord r) => r.path));
      expect(back.first.plaintext, arcadeSlots.first.plaintext);
    });
  });

  group('ArcadeDatabase', () {
    test('reads a live save whose rows only exist in the -wal', () async {
      final String db = await writeArcadeDatabase(temp);
      final LoadedSave save = await ArcadeDatabase.load(db);
      expect(save.origin, SaveOrigin.appleArcade);
      expect(save.records, hasLength(4));
      expect(save.arcadeMetadata?.deviceName, 'Test Mac');
      expect(save.arcadeMetadata?.uuid, 'UUID-KEEP-ME');
    });

    test('never modifies the files it reads', () async {
      final String db = await writeArcadeDatabase(temp);
      final Map<String, List<int>> before = snapshotFiles(temp);
      await ArcadeDatabase.load(db);
      expect(snapshotFiles(temp), before);
    });

    test('explains the missing -wal when only the .sqlite is there', () async {
      final String db = await writeArcadeDatabase(temp);
      await File('$db-wal').delete();
      await File('$db-shm').delete();
      expect(
        () => ArcadeDatabase.load(db),
        throwsA(isA<SaveException>().having((SaveException e) => e.hint, 'hint', contains('-wal'))),
      );
    });

    test('writes only ZDATA/ZTIME and leaves CloudKit tables alone', () async {
      final String db = await writeArcadeDatabase(temp);
      final List<SaveRecord> replacement = <SaveRecord>[
        SaveRecord(
          path: 'Data/GameData5.json',
          plaintext: makeSlot(playSeconds: 1, money: 2, mapId: 'X', date: 'D'),
        ),
      ];
      expect(await ArcadeDatabase.writeRecords(db, replacement), 1);

      final LoadedSave after = await ArcadeDatabase.load(db);
      expect(after.records.single.path, 'Data/GameData5.json');
      expect(after.arcadeMetadata?.uuid, 'UUID-KEEP-ME');
      final Database check = sqlite3.open(db);
      expect(check.select('SELECT ZRECORDNAME FROM ANSCKRECORDMETADATA').single['ZRECORDNAME'],
          'owned-by-this-account');
      check.close();
    });
  });

  group('SteamRootCodec', () {
    final SteamRootCodec codec = SteamRootCodec();

    test('builds a fresh file in canonical order that parses back', () {
      final SteamBuildResult result = codec.build(
        arcadeSlots,
        arcadeMetadata: const ArcadeRowMetadata(id: 'root.json', coreDataTime: 0, uuid: 'U'),
      );
      final LoadedSave back = codec.parse(result.json, sourceDescription: 'test');
      expect(back.origin, SaveOrigin.neoDimension);
      expect(back.records.map((SaveRecord r) => r.slotId), <String>['0', '10', '1', '2']);
      expect(result.added, hasLength(4));

      final JsonMap root = decodeJsonObject(result.json, what: 'test');
      expect(root['uuid'], 'U');
      // Core Data time 0 is 2001-01-01T00:00:00Z.
      expect(root['utcTick'], 631139040000000000);
      final String inner = requireString(root['dataString'], what: 'dataString');
      expect(inner, contains('encryptedString'));
      expect(inner, isNot(contains('dataString')));
    });

    test('merges into a template, replacing by path and keeping the rest', () {
      final LoadedSave template = codec.parse(
        codec.build(<SaveRecord>[
          SaveRecord(path: 'Data/GameData0.json', plaintext: makeSlot(playSeconds: 5, money: 5, mapId: 'Old', date: 'old')),
          SaveRecord(path: 'Data/GameData7.json', plaintext: makeSlot(playSeconds: 7, money: 7, mapId: 'Keep', date: 'keep')),
        ]).json,
        sourceDescription: 'template',
      );
      final SteamBuildResult merged = codec.build(arcadeSlots.sublist(0, 2), template: template);
      expect(merged.replaced, <String>['Data/GameData0.json']);
      expect(merged.added, <String>['Data/GameData1.json']);

      final LoadedSave back = codec.parse(merged.json, sourceDescription: 'merged');
      expect(back.records.map((SaveRecord r) => r.slotId), <String>['0', '1', '7']);
      expect(back.records.first.summarise().mapId, 'CityVibra');
      expect(back.records.last.summarise().mapId, 'Keep');
    });

    test('reads the root.json FantasianSGE 0.1 produced', () {
      final String inner = utf8.decode(ZLibCodec().decode(ArcadePayload.encode(arcadeSlots)));
      final String legacy = jsonEncode(<String, Object?>{
        'path': 'root.json',
        'utcTick': 8104048561000000,
        'uuid': 'U',
        'deviceName': 'Mac',
        'localPlayerName': 'localPlayer',
        'dataString': inner,
      });
      final LoadedSave save = codec.parse(legacy, sourceDescription: 'legacy');
      expect(save.origin, SaveOrigin.legacyScript);
      expect(save.records, hasLength(4));
    });
  });

  group('SaveLoader', () {
    test('loads a zip of the FANTASIAN folder, ignoring AppleDouble files', () async {
      final Directory folder = Directory(p.join(temp.path, 'FANTASIAN'));
      await writeArcadeDatabase(folder);
      final Map<String, List<int>> files = snapshotFiles(folder);
      // Zip with an independent writer, so a bug shared by the app's own zip
      // code and its reader cannot hide.
      final List<int> zip = _zip(<String, List<int>>{
        for (final MapEntry<String, List<int>> e in files.entries) 'FANTASIAN/${e.key}': e.value,
        '__MACOSX/FANTASIAN/._SaveDataEntity.sqlite': <int>[0, 1, 2],
      });
      final String zipPath = p.join(temp.path, 'save.zip');
      await File(zipPath).writeAsBytes(zip);

      final LoadedSave save = await SaveLoader().loadFiles(<String>[zipPath]);
      expect(save.records, hasLength(4));
    });

    test('loads loose .sqlite + -wal picked from different folders', () async {
      final Directory folder = Directory(p.join(temp.path, 'src'));
      final String db = await writeArcadeDatabase(folder);
      final Directory a = await Directory(p.join(temp.path, 'a')).create();
      final Directory b = await Directory(p.join(temp.path, 'b')).create();
      final String sqlite = (await File(db).copy(p.join(a.path, 'SaveDataEntity.sqlite'))).path;
      final String wal = (await File('$db-wal').copy(p.join(b.path, 'SaveDataEntity.sqlite-wal'))).path;

      final LoadedSave save = await SaveLoader().loadFiles(<String>[sqlite, wal]);
      expect(save.records, hasLength(4));
    });
  });

  group('SaveTransfer', () {
    test('mergeIntoArcade replaces in place and appends new slots', () {
      final SaveRecord newSlot = SaveRecord(
        path: 'Data/GameData4.json',
        plaintext: makeSlot(playSeconds: 4, money: 4, mapId: 'New', date: 'n'),
      );
      final SaveRecord replaced = SaveRecord(path: 'Data/GameData0.json', plaintext: newSlot.plaintext);
      final List<SaveRecord> merged = SaveTransfer.mergeIntoArcade(arcadeSlots, <SaveRecord>[replaced, newSlot]);
      expect(merged.map((SaveRecord r) => r.slotId), <String>['1', '0', '2', '10', '4']);
      expect(merged[1].plaintext, newSlot.plaintext);
    });

    test('writes straight into a save folder with a backup', () async {
      final Directory folder = Directory(p.join(temp.path, 'FANTASIAN'));
      await writeArcadeDatabase(folder);
      final SaveRecord incoming = SaveRecord(
        path: 'Data/GameData3.json',
        plaintext: makeSlot(playSeconds: 33, money: 33, mapId: 'Steam', date: 's'),
      );
      final DirectWriteResult result = await SaveTransfer().writeIntoArcadeFolder(
        saveFolder: folder.path,
        incoming: <SaveRecord>[incoming],
        backupRoot: p.join(temp.path, 'backups'),
      );
      expect(result.after.records, hasLength(5));
      expect(Directory(result.backupPath).existsSync(), isTrue);
      final LoadedSave backup = await SaveLoader().loadFolder(result.backupPath);
      expect(backup.records, hasLength(4));
    });

    test('builds a patched zip from a target save', () async {
      final Directory folder = Directory(p.join(temp.path, 'FANTASIAN'));
      await writeArcadeDatabase(folder);
      final List<int> zip = await SaveTransfer().buildPatchedArcadeZip(
        targetPaths: <String>[folder.path],
        incoming: <SaveRecord>[arcadeSlots.first],
      );
      final String zipPath = p.join(temp.path, 'patched.zip');
      await File(zipPath).writeAsBytes(zip);
      final LoadedSave save = await SaveLoader().loadFiles(<String>[zipPath]);
      expect(save.records, hasLength(4));
    });
  });
}

/// Minimal zip writer for the test (stored, no compression), independent of
/// the code under test.
List<int> _zip(Map<String, List<int>> files) {
  final BytesBuilder out = BytesBuilder();
  final BytesBuilder central = BytesBuilder();
  int count = 0;
  for (final MapEntry<String, List<int>> file in files.entries) {
    final List<int> name = utf8.encode(file.key);
    final int crc = _crc32(file.value);
    final int offset = out.length;
    out
      ..add(_u32(0x04034b50))
      ..add(_u16(20))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u32(crc))
      ..add(_u32(file.value.length))
      ..add(_u32(file.value.length))
      ..add(_u16(name.length))
      ..add(_u16(0))
      ..add(name)
      ..add(file.value);
    central
      ..add(_u32(0x02014b50))
      ..add(_u16(20))
      ..add(_u16(20))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u32(crc))
      ..add(_u32(file.value.length))
      ..add(_u32(file.value.length))
      ..add(_u16(name.length))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u32(0))
      ..add(_u32(offset))
      ..add(name);
    count++;
  }
  final int centralOffset = out.length;
  final List<int> centralBytes = central.takeBytes();
  out
    ..add(centralBytes)
    ..add(_u32(0x06054b50))
    ..add(_u16(0))
    ..add(_u16(0))
    ..add(_u16(count))
    ..add(_u16(count))
    ..add(_u32(centralBytes.length))
    ..add(_u32(centralOffset))
    ..add(_u16(0));
  return out.takeBytes();
}

List<int> _u16(int v) => <int>[v & 0xff, (v >> 8) & 0xff];
List<int> _u32(int v) => <int>[v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff];

int _crc32(List<int> data) {
  int crc = 0xffffffff;
  for (final int byte in data) {
    crc ^= byte;
    for (int k = 0; k < 8; k++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  return crc ^ 0xffffffff;
}
