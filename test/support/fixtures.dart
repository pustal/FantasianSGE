/// Synthetic saves shaped like the real ones, for tests.
///
/// Modelled on the fixtures of Fantasian-Save-Transfer: each slot is a JSON
/// object with parallel `keys`/`values` lists, indented by four like the game
/// writes it, and the Apple Arcade database keeps its rows in the `-wal` file
/// the way a live save does.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fantasian_sge/src/core/arcade_payload.dart';
import 'package:fantasian_sge/src/core/game_process.dart';
import 'package:fantasian_sge/src/core/save_models.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Builds one slot's plaintext.
String makeSlot({
  required int playSeconds,
  required int money,
  required String mapId,
  required String date,
}) {
  final Map<String, Object?> payload = <String, Object?>{
    'keys': <String>['PlayerParty', 'GameSystemInfo', 'Inventory', 'Date'],
    'values': <String>[
      jsonEncode(<String, Object?>{
        '_units': <Map<String, String>>[
          <String, String>{'characterId': 'PC001'},
        ],
      }),
      jsonEncode(<String, Object?>{'_playTimeSec': playSeconds, '_money': money, '_mapId': mapId}),
      jsonEncode(<String, Object?>{'itemTable': <String, Object?>{'keyList': <String>[]}}),
      date,
    ],
  };
  return const JsonEncoder.withIndent('    ').convert(payload);
}

/// Four slots in the non-tidy order a real save used (slot 1 before slot 0).
final List<SaveRecord> arcadeSlots = <SaveRecord>[
  SaveRecord(
    path: 'Data/GameData1.json',
    plaintext: makeSlot(playSeconds: 59700, money: 35368, mapId: 'CityVibra', date: '2021/08/23 11:42:06'),
  ),
  SaveRecord(
    path: 'Data/GameData0.json',
    plaintext: makeSlot(playSeconds: 60000, money: 35868, mapId: 'CityVibra', date: '2026/08/19 09:44:41'),
  ),
  SaveRecord(
    path: 'Data/GameData2.json',
    plaintext: makeSlot(playSeconds: 59000, money: 30000, mapId: 'CityVibra', date: '2026/08/18 09:44:41'),
  ),
  SaveRecord(
    path: 'Data/GameData10.json',
    plaintext: makeSlot(playSeconds: 3600, money: 3980, mapId: 'NewTownEn', date: '2021/06/11 11:52:45'),
  ),
];

/// Writes an Apple Arcade style `SaveDataEntity.sqlite` into [folder].
///
/// With [rowsInWal] the save row only exists in the `-wal` file, like a live
/// save; the `.sqlite` alone is then an empty checkpoint.
Future<String> writeArcadeDatabase(
  Directory folder, {
  List<SaveRecord>? slots,
  bool rowsInWal = true,
}) async {
  final Directory work = await Directory.systemTemp.createTemp('mkdb_');
  final String live = p.join(work.path, 'SaveDataEntity.sqlite');
  final Database db = sqlite3.open(live);
  db.execute('PRAGMA journal_mode=WAL');
  db.execute(
    'CREATE TABLE ZGAMEDATAENTITY (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, '
    'ZVERSION INTEGER, ZTIME FLOAT, ZDEVICENAME VARCHAR, ZID VARCHAR, '
    'ZLOCALPLAYERNAME VARCHAR, ZUUID VARCHAR, ZDATA BLOB)',
  );
  // Stand-in for the CloudKit mirroring metadata a write must not disturb.
  db.execute('CREATE TABLE ANSCKRECORDMETADATA (Z_PK INTEGER, ZRECORDNAME TEXT)');
  db.execute("INSERT INTO ANSCKRECORDMETADATA VALUES (1, 'owned-by-this-account')");
  if (rowsInWal) {
    db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    db.execute('PRAGMA wal_autocheckpoint=0');
  }
  final Uint8List blob = ArcadePayload.encode(slots ?? arcadeSlots);
  db.execute(
    'INSERT INTO ZGAMEDATAENTITY (Z_PK, Z_ENT, Z_OPT, ZVERSION, ZTIME, ZDEVICENAME, ZID, ZUUID, ZDATA) '
    'VALUES (7, 1, 1, 0, ?, ?, ?, ?, ?)',
    <Object?>[810404856.1, 'Test Mac', 'root.json', 'UUID-KEEP-ME', blob],
  );

  // Copy while the connection is still open, so the -wal keeps the rows.
  await folder.create(recursive: true);
  for (final String suffix in <String>['', '-wal', '-shm']) {
    final File file = File('$live$suffix');
    if (file.existsSync()) {
      await file.copy(p.join(folder.path, 'SaveDataEntity.sqlite$suffix'));
    }
  }
  db.close();
  await work.delete(recursive: true);
  return p.join(folder.path, 'SaveDataEntity.sqlite');
}

/// Reads every byte of the database files in [folder], to prove reads never
/// modify them.
Map<String, List<int>> snapshotFiles(Directory folder) => <String, List<int>>{
  for (final FileSystemEntity entity in folder.listSync()..sort((FileSystemEntity a, FileSystemEntity b) => a.path.compareTo(b.path)))
    if (entity is File) p.basename(entity.path): entity.readAsBytesSync(),
};

/// A stand-in for the FANTASIAN process, so tests decide whether "the game"
/// is running instead of depending on what runs on the test machine (a real
/// `pgrep` on a Mac answers "not running", on Linux "unknown").
class FakeGame {
  /// Creates a fake game that starts closed.
  FakeGame({this.running = false});

  /// Whether the fake game is open.
  bool running;

  /// A [GameRunCheck] reporting [running].
  Future<GameRunState> check() async =>
      running ? GameRunState.running : GameRunState.notRunning;
}
