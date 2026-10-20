/// Turns whatever the player picked (a folder, a zip, a `.sqlite` with or
/// without its sidecars, or a `root.json`) into a [LoadedSave].
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'arcade_database.dart';
import 'constants.dart';
import 'save_exception.dart';
import 'save_models.dart';
import 'steam_root.dart';

/// A temporary folder holding an Apple Arcade database and its sidecars under
/// their canonical names. Call [dispose] when done with it.
final class StagedArcadeFolder {
  /// Wraps an already populated temporary [directory].
  const StagedArcadeFolder(this.directory);

  /// The temporary folder.
  final Directory directory;

  /// Path of the `.sqlite` inside [directory].
  String get databasePath => p.join(directory.path, ArcadeConstants.databaseFileName);

  /// Deletes the temporary folder.
  Future<void> dispose() async {
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  }
}

/// Loads saves from player-picked locations.
final class SaveLoader {
  /// Creates a loader that parses Steam files with [steamCodec].
  SaveLoader({SteamRootCodec? steamCodec}) : _steam = steamCodec ?? SteamRootCodec();

  final SteamRootCodec _steam;

  /// Loads a save from a folder that contains `SaveDataEntity.sqlite`
  /// (an Apple Arcade save folder) or a `root.json`.
  Future<LoadedSave> loadFolder(String folderPath) async {
    final Directory folder = Directory(folderPath);
    final String? database = ArcadeDatabase.databaseIn(folder);
    if (database != null) {
      return ArcadeDatabase.load(database);
    }
    final File root = File(p.join(folderPath, SteamConstants.rootFileName));
    if (root.existsSync()) {
      return loadSteamFile(root.path);
    }
    throw SaveException(
      'No ${ArcadeConstants.databaseFileName} or ${SteamConstants.rootFileName} '
      'inside $folderPath.',
    );
  }

  /// Loads a save from one or more picked files.
  ///
  /// * a `.json` file is read as a `root.json`;
  /// * a `.zip` must contain a FANTASIAN folder (or at least its database);
  /// * `SaveDataEntity.sqlite*` files are staged together, with any sidecars
  ///   found next to the `.sqlite` on disk.
  Future<LoadedSave> loadFiles(List<String> paths) async {
    if (paths.isEmpty) {
      throw const SaveException('No file was picked.');
    }
    final String? json = _firstWithExtension(paths, '.json');
    if (json != null) {
      return loadSteamFile(json);
    }
    final StagedArcadeFolder staged = await stageArcade(paths);
    try {
      final LoadedSave save = await ArcadeDatabase.load(staged.databasePath);
      return LoadedSave(
        origin: save.origin,
        sourceDescription: paths.map(p.basename).join(', '),
        records: save.records,
        arcadeMetadata: save.arcadeMetadata,
      );
    } finally {
      await staged.dispose();
    }
  }

  /// Parses a `root.json` file at [path].
  Future<LoadedSave> loadSteamFile(String path) async {
    final String text;
    try {
      text = await File(path).readAsString();
    } on FileSystemException catch (error) {
      throw SaveException('Could not read $path (${error.message}).');
    }
    return _steam.parse(text, sourceDescription: path);
  }

  /// Copies an Apple Arcade database, from a zip, a folder or loose files,
  /// into a fresh temporary folder under canonical names.
  Future<StagedArcadeFolder> stageArcade(List<String> paths) async {
    final Directory target = await Directory.systemTemp.createTemp('fantasian_stage_');
    final StagedArcadeFolder staged = StagedArcadeFolder(target);
    try {
      for (final String path in paths) {
        if (FileSystemEntity.isDirectorySync(path)) {
          final String? database = ArcadeDatabase.databaseIn(Directory(path));
          if (database != null) {
            await _copyDatabaseFiles(database, target);
          }
        } else if (p.extension(path).toLowerCase() == '.zip') {
          await _extractZip(path, target);
        } else if (_isDatabaseFileName(p.basename(path))) {
          await _copyPickedDatabaseFile(path, target);
        }
      }
      if (!File(staged.databasePath).existsSync()) {
        throw const SaveException(
          'None of the picked items contains ${ArcadeConstants.databaseFileName}.',
          hint: 'Pick the FANTASIAN save folder, a zip of it, or the .sqlite file '
              'together with its -wal and -shm files.',
        );
      }
      return staged;
    } on Object {
      await staged.dispose();
      rethrow;
    }
  }

  /// Copies a picked `SaveDataEntity.sqlite[-wal|-shm]` into [target]. When
  /// the main `.sqlite` is picked, sidecars sitting next to it come too.
  Future<void> _copyPickedDatabaseFile(String path, Directory target) async {
    final String name = p.basename(path);
    if (name == ArcadeConstants.databaseFileName) {
      await _copyDatabaseFiles(path, target);
    } else {
      await File(path).copy(p.join(target.path, name));
    }
  }

  /// Copies the database at [databasePath] and its sidecars into [target].
  Future<void> _copyDatabaseFiles(String databasePath, Directory target) async {
    for (final File file in ArcadeDatabase.saveFiles(databasePath)) {
      final String suffix = file.path.substring(databasePath.length);
      await file.copy(p.join(target.path, '${ArcadeConstants.databaseFileName}$suffix'));
    }
  }

  /// Extracts only the database files from the zip at [zipPath].
  Future<void> _extractZip(String zipPath, Directory target) async {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(await File(zipPath).readAsBytes());
    } on Object {
      throw SaveException('${p.basename(zipPath)} is not a readable zip file.');
    }
    for (final ArchiveFile entry in archive.files) {
      final String name = p.basename(entry.name);
      // Skip folders and the "._" AppleDouble files macOS adds to zips.
      if (!entry.isFile || name.startsWith('._') || !_isDatabaseFileName(name)) {
        continue;
      }
      final Uint8List? bytes = entry.readBytes();
      if (bytes != null) {
        await File(p.join(target.path, name)).writeAsBytes(bytes, flush: true);
      }
    }
  }

  /// Whether [name] is the database or one of its sidecars.
  static bool _isDatabaseFileName(String name) => <String>[
    ArcadeConstants.databaseFileName,
    for (final String suffix in ArcadeConstants.sidecarSuffixes)
      '${ArcadeConstants.databaseFileName}$suffix',
  ].contains(name);

  /// The first path in [paths] with [extension] (case-insensitive).
  static String? _firstWithExtension(List<String> paths, String extension) {
    for (final String path in paths) {
      if (p.extension(path).toLowerCase() == extension) {
        return path;
      }
    }
    return null;
  }
}
