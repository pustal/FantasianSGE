/// Converts between the Apple Arcade `ZDATA` blob and [SaveRecord]s.
///
/// The blob is zlib-compressed JSON of the shape
/// `{"records":[{"path":"Data/GameData0.json","dataString":"<save json>"}]}`.
library;

import 'dart:convert';
import 'dart:io' show ZLibCodec;
import 'dart:typed_data';

import 'json_reading.dart';
import 'save_exception.dart';
import 'save_models.dart';

/// The first byte of every zlib stream written with the default window size.
const int _zlibHeaderByte = 0x78;

/// Decodes and encodes the Apple Arcade save container.
abstract final class ArcadePayload {
  /// Decompresses [blob] (if compressed) and returns its records.
  ///
  /// Also accepts the uncompressed JSON, and the legacy FantasianSGE 0.1
  /// `root.json` wrapper whose `dataString` holds the same container.
  static List<SaveRecord> decode(Uint8List blob) {
    Uint8List raw = blob;
    if (raw.isNotEmpty && raw.first == _zlibHeaderByte) {
      try {
        raw = Uint8List.fromList(ZLibCodec().decode(raw));
      } on FormatException {
        throw const SaveException('The Apple Arcade save data is corrupt (zlib error).');
      }
    }
    final String text;
    try {
      text = utf8.decode(raw);
    } on FormatException {
      throw const SaveException('The Apple Arcade save data is not text after decompression.');
    }
    return recordsFromContainer(decodeJsonObject(text, what: 'The save container'));
  }

  /// Reads the `records` list out of a container object, unwrapping one level
  /// of `dataString` if needed (the legacy `root.json` shape).
  static List<SaveRecord> recordsFromContainer(JsonMap container) {
    JsonMap object = container;
    if (!object.containsKey('records') && object['dataString'] is String) {
      object = decodeJsonObject(
        requireString(object['dataString'], what: 'dataString'),
        what: 'The inner save container',
      );
    }
    final List<Object?> list = requireList(object['records'], what: 'records');
    if (list.isEmpty) {
      throw const SaveException('That file holds no save slots.');
    }
    return <SaveRecord>[
      for (final Object? entry in list) _plainRecord(requireMap(entry, what: 'A save record')),
    ];
  }

  /// Builds the compressed blob the game stores in `ZDATA`.
  ///
  /// Records keep the order they are given in: the game addresses slots by
  /// path, and keeping its own order avoids rewriting more than necessary.
  static Uint8List encode(List<SaveRecord> records) {
    final Map<String, Object?> container = <String, Object?>{
      'records': <Map<String, String>>[
        for (final SaveRecord record in records)
          <String, String>{'path': record.path, 'dataString': record.plaintext},
      ],
    };
    final List<int> json = utf8.encode(jsonEncode(container));
    return Uint8List.fromList(ZLibCodec(level: 9).encode(json));
  }

  /// Turns one container entry into a [SaveRecord]. Apple Arcade entries
  /// carry plain JSON in `dataString`.
  static SaveRecord _plainRecord(JsonMap entry) {
    final String path = requireString(entry['path'], what: 'A record path');
    final String? data = optionalString(entry['dataString']);
    if (data == null) {
      throw SaveException('$path holds no save data.');
    }
    return SaveRecord(path: path, plaintext: data);
  }
}
