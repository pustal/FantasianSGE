/// Reads and writes the Apple Arcade Core Data store, `SaveDataEntity.sqlite`.
///
/// Two rules shape this file:
///
/// * **Reads always happen on a copy.** Opening a SQLite database that has a
///   write-ahead log folds the log back into the main file, which is a real
///   modification of the player's save. So the `.sqlite` and its `-wal` /
///   `-shm` sidecars are copied to a temporary folder first.
/// * **The three files travel together.** The game's current progress usually
///   lives in the `-wal`; the `.sqlite` alone can hold no slots at all.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'arcade_payload.dart';
import 'constants.dart';
import 'save_exception.dart';
import 'save_models.dart';

/// One `ZGAMEDATAENTITY` row that holds a save container.
final class _SaveRow {
  const _SaveRow({required this.primaryKey, required this.blob, required this.metadata});

  final int primaryKey;
  final Uint8List blob;
  final ArcadeRowMetadata metadata;
}

/// Access to Apple Arcade save databases.
abstract final class ArcadeDatabase {
  /// Every file that makes up the database at [databasePath] and exists on
  /// disk: the `.sqlite` itself plus whichever sidecars are present.
  static List<File> saveFiles(String databasePath) => <File>[
    for (final String suffix in <String>['', ...ArcadeConstants.sidecarSuffixes])
      if (File('$databasePath$suffix').existsSync()) File('$databasePath$suffix'),
  ];

  /// The database inside [folder], or `null` if the folder has none.
  static String? databaseIn(Directory folder) {
    final String candidate = p.join(folder.path, ArcadeConstants.databaseFileName);
    return File(candidate).existsSync() ? candidate : null;
  }

  /// Loads the newest save container from the database at [databasePath],
  /// reading from a temporary copy so the original is never modified.
  static Future<LoadedSave> load(String databasePath) async {
    final _SaveRow row = await _newestRow(databasePath);
    return LoadedSave(
      origin: SaveOrigin.appleArcade,
      sourceDescription: databasePath,
      records: ArcadePayload.decode(row.blob),
      arcadeMetadata: row.metadata,
    );
  }

  /// Replaces the save container in the database at [databasePath] with
  /// [records], in place.
  ///
  /// Only `ZDATA` and `ZTIME` change; every Core Data and CloudKit bookkeeping
  /// table is left exactly as it was, so the database keeps the identity of
  /// the Apple account that owns it. The caller is responsible for backups
  /// and for making sure the game is not running.
  ///
  /// Returns how many rows were updated.
  static Future<int> writeRecords(String databasePath, List<SaveRecord> records) async {
    // Find the rows to update from a copy, so a database that turns out not to
    // be a FANTASIAN save is never opened for writing.
    final List<_SaveRow> rows = await _saveRows(databasePath);
    final Uint8List blob = ArcadePayload.encode(records);
    final double now = coreDataNow();

    final Database db = sqlite3.open(databasePath);
    try {
      db.execute('BEGIN');
      for (final _SaveRow row in rows) {
        db.execute(
          'UPDATE ${ArcadeConstants.table} SET ZDATA = ?, ZTIME = ? WHERE Z_PK = ?',
          <Object?>[blob, now, row.primaryKey],
        );
      }
      db.execute('COMMIT');
    } on Object {
      db.execute('ROLLBACK');
      rethrow;
    } finally {
      db.close();
    }
    return rows.length;
  }

  /// The current time in Core Data's unit (seconds since 2001-01-01 UTC).
  static double coreDataNow() =>
      DateTime.now().millisecondsSinceEpoch / 1000 - ArcadeConstants.coreDataEpochOffsetSeconds;

  /// The most recently written save row.
  static Future<_SaveRow> _newestRow(String databasePath) async =>
      (await _saveRows(databasePath)).first;

  /// All rows holding a save container, newest first, read from a copy.
  static Future<List<_SaveRow>> _saveRows(String databasePath) async {
    if (!File(databasePath).existsSync()) {
      throw SaveException('There is no file at $databasePath.');
    }
    final Directory scratch = await Directory.systemTemp.createTemp('fantasian_read_');
    try {
      final String copy = p.join(scratch.path, ArcadeConstants.databaseFileName);
      int sidecars = 0;
      for (final File file in saveFiles(databasePath)) {
        final String suffix = file.path.substring(databasePath.length);
        await file.copy('$copy$suffix');
        if (suffix.isNotEmpty) {
          sidecars++;
        }
      }
      final List<_SaveRow> rows = _queryRows(copy, sidecarCount: sidecars);
      if (rows.isEmpty) {
        throw _noSaveError(sidecars, 'it holds no save rows');
      }
      return rows;
    } finally {
      await scratch.delete(recursive: true);
    }
  }

  /// Runs the row query against the (copied) database at [path].
  static List<_SaveRow> _queryRows(String path, {required int sidecarCount}) {
    final Database db;
    try {
      db = sqlite3.open(path);
    } on SqliteException catch (error) {
      throw _noSaveError(sidecarCount, error.message);
    }
    try {
      final Set<String> columns = _columnsOf(db, ArcadeConstants.table);
      if (columns.isEmpty) {
        throw _noSaveError(sidecarCount, 'there is no ${ArcadeConstants.table} table');
      }
      // Only ask for optional columns that this build of the game has.
      String optional(String column) => columns.contains(column) ? column : 'NULL';
      final ResultSet result = db.select(
        'SELECT Z_PK, ZID, ZDATA, ${optional('ZTIME')} AS ZTIME, '
        '${optional('ZDEVICENAME')} AS ZDEVICENAME, ${optional('ZUUID')} AS ZUUID, '
        '${optional('ZLOCALPLAYERNAME')} AS ZLOCALPLAYERNAME '
        'FROM ${ArcadeConstants.table} ORDER BY ZTIME DESC',
      );
      final List<_SaveRow> rows = <_SaveRow>[];
      for (final Row row in result) {
        final Object? id = row['ZID'];
        final Object? blob = row['ZDATA'];
        final Object? primaryKey = row['Z_PK'];
        // Keep only rows that are save containers (ZID is "root.json").
        if (id is! String || !id.toLowerCase().contains('root')) {
          continue;
        }
        if (blob is! Uint8List || blob.isEmpty || primaryKey is! int) {
          continue;
        }
        final Object? time = row['ZTIME'];
        rows.add(
          _SaveRow(
            primaryKey: primaryKey,
            blob: blob,
            metadata: ArcadeRowMetadata(
              id: id,
              coreDataTime: time is num ? time.toDouble() : null,
              deviceName: _text(row['ZDEVICENAME']),
              uuid: _text(row['ZUUID']),
              localPlayerName: _text(row['ZLOCALPLAYERNAME']),
            ),
          ),
        );
      }
      return rows;
    } on SqliteException catch (error) {
      throw _noSaveError(sidecarCount, error.message);
    } finally {
      db.close();
    }
  }

  /// Column names of [table], or an empty set when the table does not exist.
  static Set<String> _columnsOf(Database db, String table) => <String>{
    for (final Row row in db.select('PRAGMA table_info($table)'))
      if (row['name'] case final String name) name,
  };

  /// A trimmed non-empty string, or `null`.
  static String? _text(Object? value) {
    if (value is! String) {
      return null;
    }
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// The error for a database without a usable save, with advice that depends
  /// on whether the `-wal` sidecar came along.
  static SaveException _noSaveError(int sidecarCount, String detail) {
    if (sidecarCount > 0) {
      return SaveException(
        'There is no FANTASIAN save in this database ($detail).',
        hint: 'Its -wal file was read too, so this does not look like a FANTASIAN save.',
      );
    }
    return SaveException(
      'There is no FANTASIAN save in this database ($detail), and its -wal file '
      'was not next to it.',
      hint: 'FANTASIAN keeps current progress in SaveDataEntity.sqlite-wal. Copy the '
          'whole FANTASIAN folder (or a zip of it), or pick the .sqlite together '
          'with its -wal and -shm files.',
    );
  }
}
