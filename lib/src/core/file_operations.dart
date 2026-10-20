/// File-system helpers shared by the export and insert workflows: backups,
/// swapping the save files, and writing outputs.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'arcade_database.dart';
import 'constants.dart';

/// Backups and file swaps.
abstract final class FileOperations {
  /// A sortable timestamp for backup names, e.g. `20261020_163804`.
  static String timestamp([DateTime? at]) {
    final DateTime t = at ?? DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}_${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }

  /// Copies [path] to `<path>.backup_<timestamp>` and returns the copy's path.
  static Future<String> backupFile(String path) async {
    final String destination = '$path.backup_${timestamp()}';
    await File(path).copy(destination);
    return destination;
  }

  /// Copies the whole [folder] into a new timestamped folder inside
  /// [backupRoot] and returns the new folder's path.
  static Future<String> backupFolder(String folder, {required String backupRoot}) async {
    final String destination = p.join(backupRoot, 'FANTASIAN-backup-${timestamp()}');
    await copyDirectory(Directory(folder), Directory(destination));
    return destination;
  }

  /// Recursively copies [source] into [destination] (created if missing).
  static Future<void> copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final FileSystemEntity entity in source.list(followLinks: false)) {
      final String target = p.join(destination.path, p.basename(entity.path));
      if (entity is Directory) {
        await copyDirectory(entity, Directory(target));
      } else if (entity is File) {
        await entity.copy(target);
      }
    }
  }

  /// Copies only the database files of [sourceFolder] into [destinationFolder].
  static Future<void> copySaveFiles(String sourceFolder, String destinationFolder) async {
    await Directory(destinationFolder).create(recursive: true);
    final String database = p.join(sourceFolder, ArcadeConstants.databaseFileName);
    for (final File file in ArcadeDatabase.saveFiles(database)) {
      await file.copy(p.join(destinationFolder, p.basename(file.path)));
    }
  }

  /// Deletes the database files in [destinationFolder] and puts the ones from
  /// [sourceFolder] there instead.
  ///
  /// This must stay a delete-then-copy. It gives the files new inodes, which
  /// is what Finder's "Replace" does and what lets a running game see the new
  /// saves the next time it opens its Load screen. Overwriting in place keeps
  /// the inode, but SQLite has the `-shm` memory-mapped, and the game then
  /// stops seeing the database at all (observed by Fantasian-Save-Transfer on
  /// game version 2.5.3).
  static Future<void> replaceSaveFiles({
    required String sourceFolder,
    required String destinationFolder,
  }) async {
    final String destinationDb = p.join(destinationFolder, ArcadeConstants.databaseFileName);
    for (final File file in ArcadeDatabase.saveFiles(destinationDb)) {
      await file.delete();
    }
    await copySaveFiles(sourceFolder, destinationFolder);
  }

  /// Writes [contents] to [path], flushing to disk.
  static Future<void> writeText(String path, String contents) async {
    await File(path).writeAsString(contents, flush: true);
  }
}
