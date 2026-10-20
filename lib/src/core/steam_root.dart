/// Reads and writes FANTASIAN Neo Dimension's `root.json`.
///
/// Shape (the inner object is itself serialised into the `dataString` text):
///
/// ```json
/// {
///   "path": "root.json", "utcTick": 0, "uuid": "...", "deviceName": "...",
///   "localPlayerName": "...",
///   "dataString": "{\"records\":[{\"path\":\"Data/GameData0.json\",
///                                 \"encryptedString\":\"<base64 AES>\"}]}"
/// }
/// ```
library;

import 'dart:convert';

import 'constants.dart';
import 'json_reading.dart';
import 'save_exception.dart';
import 'save_models.dart';
import 'steam_crypto.dart';

/// The result of building a `root.json`: its text plus a report of which
/// slots were added and which replaced a slot already in the template.
final class SteamBuildResult {
  /// Creates a build result.
  const SteamBuildResult({
    required this.json,
    required this.slotCount,
    required this.added,
    required this.replaced,
  });

  /// The file contents, ready to write.
  final String json;

  /// How many slots the file holds in total.
  final int slotCount;

  /// Paths of slots that were not in the template.
  final List<String> added;

  /// Paths of slots that overwrote a template slot.
  final List<String> replaced;
}

/// Parses and builds Neo Dimension save files.
final class SteamRootCodec {
  /// Creates a codec using [crypto] (defaults to the game's own key).
  SteamRootCodec({SteamCrypto? crypto}) : _crypto = crypto ?? SteamCrypto();

  final SteamCrypto _crypto;

  /// Parses the text of a `root.json`.
  ///
  /// Recognises both the real Neo Dimension format (encrypted records) and
  /// the unencrypted file FantasianSGE 0.1 produced.
  LoadedSave parse(String text, {required String sourceDescription}) {
    final JsonMap root = decodeJsonObject(text, what: 'That root.json');
    final String? inner = optionalString(root['dataString']);
    if (inner == null) {
      throw const SaveException(
        'That file is not a FANTASIAN root.json (it has no dataString).',
      );
    }
    final JsonMap container = decodeJsonObject(inner, what: 'The root.json dataString');
    final List<Object?> entries = requireList(container['records'], what: 'records');
    if (entries.isEmpty) {
      throw const SaveException('That root.json holds no save slots.');
    }

    bool sawEncrypted = false;
    final List<SaveRecord> records = <SaveRecord>[];
    for (final Object? rawEntry in entries) {
      final JsonMap entry = requireMap(rawEntry, what: 'A save record');
      final String path = requireString(entry['path'], what: 'A record path');
      // Neo Dimension reads encryptedString; prefer it whenever present, even
      // if a stale dataString sits beside it.
      final String? encrypted = optionalString(entry['encryptedString']);
      final String? plain = optionalString(entry['dataString']);
      if (encrypted != null) {
        sawEncrypted = true;
        records.add(SaveRecord(path: path, plaintext: _crypto.decryptRecord(encrypted)));
      } else if (plain != null) {
        records.add(SaveRecord(path: path, plaintext: plain));
      } else {
        throw SaveException('$path holds no save data.');
      }
    }

    return LoadedSave(
      origin: sawEncrypted ? SaveOrigin.neoDimension : SaveOrigin.legacyScript,
      sourceDescription: sourceDescription,
      records: records,
      steamRoot: root,
    );
  }

  /// Builds a Neo Dimension `root.json` holding [records].
  ///
  /// When [template] (an existing Neo Dimension save) is given, its slots are
  /// kept and only slots with the same path are replaced, so Steam progress in
  /// other slots survives. Every top-level field of the template is kept.
  /// Without a template, a fresh file is written with the same top-level
  /// fields the original FantasianSGE script produced, filled from
  /// [arcadeMetadata] when available.
  ///
  /// Every record is decrypted and parsed again before returning, so a file
  /// that would not load is never handed back.
  SteamBuildResult build(
    List<SaveRecord> records, {
    LoadedSave? template,
    ArcadeRowMetadata? arcadeMetadata,
    DateTime? now,
  }) {
    if (records.isEmpty) {
      throw const SaveException('Pick at least one slot to bring across.');
    }
    if (template != null && template.origin != SaveOrigin.neoDimension) {
      throw const SaveException('The merge target must be a Neo Dimension root.json.');
    }

    // Start from the template's slots (re-encrypted from their plaintext,
    // which round-trips byte for byte) and overlay the new ones by path.
    final Map<String, SaveRecord> byPath = <String, SaveRecord>{
      for (final SaveRecord record in template?.records ?? const <SaveRecord>[])
        record.path: record,
    };
    final List<String> added = <String>[];
    final List<String> replaced = <String>[];
    for (final SaveRecord record in records) {
      (byPath.containsKey(record.path) ? replaced : added).add(record.path);
      byPath[record.path] = record;
    }
    final List<SaveRecord> ordered = canonicalOrder(byPath.values);

    final List<Map<String, String>> encryptedRecords = <Map<String, String>>[
      for (final SaveRecord record in ordered)
        <String, String>{
          'path': record.path,
          'encryptedString': _crypto.encryptRecord(record.plaintext),
        },
    ];

    final Map<String, Object?> root = template?.steamRoot != null
        ? Map<String, Object?>.of(template!.steamRoot!)
        : _freshRootFields(arcadeMetadata, now ?? DateTime.now().toUtc());
    root['dataString'] = jsonEncode(<String, Object?>{'records': encryptedRecords});

    final String text = const JsonEncoder.withIndent('    ').convert(root);
    _verify(text, expected: ordered);

    return SteamBuildResult(
      json: text,
      slotCount: ordered.length,
      added: added,
      replaced: replaced,
    );
  }

  /// Orders records as `GameData0, GameData10, GameData1 ... GameData9`, then
  /// anything unusual by name.
  ///
  /// This is the layout real Neo Dimension files use, and the community save
  /// editor addresses slots by position in it, so keeping it avoids that
  /// editor touching the wrong slot later. The game itself reads by path.
  static List<SaveRecord> canonicalOrder(Iterable<SaveRecord> records) {
    int rank(SaveRecord record) {
      final int? number = record.slotNumber;
      if (number == null) {
        return 1000;
      }
      if (number == 0) {
        return 0;
      }
      return number == 10 ? 1 : number + 1;
    }

    final List<SaveRecord> sorted = records.toList()
      ..sort((SaveRecord a, SaveRecord b) {
        final int byRank = rank(a).compareTo(rank(b));
        return byRank != 0 ? byRank : a.path.compareTo(b.path);
      });
    return sorted;
  }

  /// Top-level fields for a brand-new file, mirroring FantasianSGE 0.1.
  Map<String, Object?> _freshRootFields(ArcadeRowMetadata? meta, DateTime now) {
    final double? coreDataTime = meta?.coreDataTime;
    final DateTime savedAt = coreDataTime == null
        ? now
        : DateTime.fromMillisecondsSinceEpoch(
            ((coreDataTime + ArcadeConstants.coreDataEpochOffsetSeconds) * 1000).round(),
            isUtc: true,
          );
    return <String, Object?>{
      'path': meta?.id ?? SteamConstants.rootFileName,
      'utcTick': dotNetTicks(savedAt),
      'uuid': meta?.uuid ?? '',
      'deviceName': meta?.deviceName ?? '',
      'localPlayerName': meta?.localPlayerName ?? 'localPlayer',
    };
  }

  /// Converts [time] to .NET `DateTime.Ticks` (100 ns units since
  /// 0001-01-01 UTC), the unit of the game's `utcTick` field.
  ///
  /// FantasianSGE 0.1 multiplied the raw Core Data seconds by 10^7 instead;
  /// this is the corrected conversion.
  static int dotNetTicks(DateTime time) {
    final int micros = time.toUtc().microsecondsSinceEpoch;
    return (SteamConstants.dotNetEpochOffsetSeconds * SteamConstants.ticksPerSecond) +
        micros * 10;
  }

  /// Parses [text] back and checks every slot matches [expected].
  void _verify(String text, {required List<SaveRecord> expected}) {
    final LoadedSave back = parse(text, sourceDescription: 'verification');
    final bool same = back.records.length == expected.length &&
        <bool>[
          for (int i = 0; i < expected.length; i++)
            back.records[i].path == expected[i].path &&
                back.records[i].plaintext == expected[i].plaintext,
        ].every((bool ok) => ok);
    if (!same) {
      throw const SaveException(
        'The converted save did not read back identically, so nothing was written.',
      );
    }
  }
}
