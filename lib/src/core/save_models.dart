/// Plain data types describing a loaded save, independent of which release of
/// the game wrote it.
library;

import 'dart:convert';

import 'json_reading.dart';

/// Which kind of file a save was read from.
enum SaveOrigin {
  /// An Apple Arcade Core Data database (`SaveDataEntity.sqlite`).
  appleArcade('Apple Arcade'),

  /// A FANTASIAN Neo Dimension `root.json` with encrypted records.
  neoDimension('Neo Dimension (Steam)'),

  /// A `root.json` written by FantasianSGE 0.1 (the original shell script),
  /// which holds the Apple Arcade records unencrypted.
  legacyScript('FantasianSGE 0.1 root.json');

  const SaveOrigin(this.label);

  /// Human-readable name shown in the UI.
  final String label;
}

/// One save slot: the game's file path for it (`Data/GameData3.json`) and the
/// save itself as plain JSON text, decrypted if it came from Steam.
final class SaveRecord {
  /// Creates a record from its [path] and decrypted [plaintext].
  const SaveRecord({required this.path, required this.plaintext});

  /// The game's own name for the slot file, e.g. `Data/GameData0.json`.
  final String path;

  /// The save payload: a JSON object with parallel `keys` and `values` lists.
  final String plaintext;

  /// The slot number taken from [path] (`GameData3.json` -> `3`), or the bare
  /// file name when the path does not follow that pattern.
  String get slotId {
    final String base = path.split('/').last;
    const String prefix = 'GameData';
    const String suffix = '.json';
    if (base.startsWith(prefix) && base.endsWith(suffix)) {
      return base.substring(prefix.length, base.length - suffix.length);
    }
    return base;
  }

  /// The slot number as an integer, or `null` for unusual file names.
  int? get slotNumber => int.tryParse(slotId);

  /// The file name shown to players, e.g. `GameData3`.
  String get fileLabel => slotNumber == null ? slotId : 'GameData$slotId';

  /// What the game's Load screen calls this slot. Checked against the macOS
  /// build by the Fantasian-Save-Transfer project: `GameData0` is the
  /// autosave and `GameData<N>` is manual Slot N (1-10).
  String get gameLabel {
    final int? number = slotNumber;
    if (number == null) {
      return 'Unknown slot';
    }
    return number == 0 ? 'Autosave' : 'Slot $number';
  }

  /// Reads the bits worth showing in a slot list. Never throws: a slot that
  /// cannot be summarised is reported through [SlotSummary.problem].
  SlotSummary summarise() {
    try {
      final JsonMap root = decodeJsonObject(plaintext, what: fileLabel);
      final List<Object?> keys = requireList(root['keys'], what: '$fileLabel keys');
      final List<Object?> values = requireList(root['values'], what: '$fileLabel values');
      final Map<String, Object?> sections = <String, Object?>{
        for (int i = 0; i < keys.length && i < values.length; i++)
          if (keys[i] case final String key) key: values[i],
      };

      JsonMap info = <String, Object?>{};
      if (sections['GameSystemInfo'] case final String rawInfo) {
        final Object? decoded = jsonDecode(rawInfo);
        if (decoded is Map<String, Object?>) {
          info = decoded;
        }
      }
      final num? seconds = optionalNum(info['_playTimeSec']);
      final num? money = optionalNum(info['_money']);
      return SlotSummary(
        savedAt: optionalString(sections['Date']),
        playTime: seconds == null ? null : Duration(seconds: seconds.round()),
        money: money?.round(),
        mapId: optionalString(info['_mapId']),
      );
    } on Object catch (error) {
      return SlotSummary(problem: error.toString());
    }
  }
}

/// A short description of one slot for display.
final class SlotSummary {
  /// Creates a summary; every field is optional because saves vary.
  const SlotSummary({
    this.savedAt,
    this.playTime,
    this.money,
    this.mapId,
    this.problem,
  });

  /// The in-game save date string, e.g. `2025/03/14 21:08:52`.
  final String? savedAt;

  /// Total play time.
  final Duration? playTime;

  /// Gil carried.
  final int? money;

  /// Internal id of the map the party is on, e.g. `CityVibra`.
  final String? mapId;

  /// Set when the slot could not be read.
  final String? problem;
}

/// Metadata the Apple Arcade database keeps beside the save and that the
/// original FantasianSGE script copied into `root.json`.
final class ArcadeRowMetadata {
  /// Creates the metadata for one `ZGAMEDATAENTITY` row.
  const ArcadeRowMetadata({
    required this.id,
    this.coreDataTime,
    this.deviceName,
    this.uuid,
    this.localPlayerName,
  });

  /// `ZID`, normally `root.json`.
  final String id;

  /// `ZTIME`: seconds since 2001-01-01 UTC (Core Data's reference date).
  final double? coreDataTime;

  /// `ZDEVICENAME`: the Mac or iPhone that last saved.
  final String? deviceName;

  /// `ZUUID`.
  final String? uuid;

  /// `ZLOCALPLAYERNAME`, when Game Center provided one.
  final String? localPlayerName;
}

/// Everything read from one save file or folder.
final class LoadedSave {
  /// Creates a loaded save.
  const LoadedSave({
    required this.origin,
    required this.sourceDescription,
    required this.records,
    this.arcadeMetadata,
    this.steamRoot,
  });

  /// What kind of file this came from.
  final SaveOrigin origin;

  /// Where it came from, for display (a path or a file name).
  final String sourceDescription;

  /// The save slots, in the order the file stored them.
  final List<SaveRecord> records;

  /// Row metadata, when the source was an Apple Arcade database.
  final ArcadeRowMetadata? arcadeMetadata;

  /// The whole top-level `root.json` object, when the source was one. Kept so
  /// a merge can preserve every field other than the save records.
  final JsonMap? steamRoot;

  /// Returns a copy that keeps only the records whose [SaveRecord.path] is in
  /// [paths], preserving order.
  LoadedSave onlyPaths(Set<String> paths) => LoadedSave(
    origin: origin,
    sourceDescription: sourceDescription,
    records: <SaveRecord>[
      for (final SaveRecord record in records)
        if (paths.contains(record.path)) record,
    ],
    arcadeMetadata: arcadeMetadata,
    steamRoot: steamRoot,
  );
}
