/// High-level operations behind the Extract and Insert screens.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'arcade_database.dart';
import 'constants.dart';
import 'file_operations.dart';
import 'game_process.dart';
import 'save_exception.dart';
import 'save_loader.dart';
import 'save_models.dart';
import 'steam_root.dart';

/// What a direct write into the Mac save folder did.
final class DirectWriteResult {
  /// Creates a result.
  const DirectWriteResult({required this.backupPath, required this.after});

  /// Where the previous save folder was copied before writing.
  final String backupPath;

  /// The save as read back from disk after the write.
  final LoadedSave after;
}

/// Conversions and installs between the two releases.
final class SaveTransfer {
  /// Creates the service.
  SaveTransfer({SteamRootCodec? steamCodec, SaveLoader? loader})
    : _steam = steamCodec ?? SteamRootCodec(),
      _loader = loader ?? SaveLoader();

  final SteamRootCodec _steam;
  final SaveLoader _loader;

  // ---------------------------------------------------------------------------
  // Apple Arcade -> Neo Dimension
  // ---------------------------------------------------------------------------

  /// Builds a Neo Dimension `root.json` from the slots of [source] whose path
  /// is in [selectedPaths], optionally merged into [template].
  SteamBuildResult buildSteamRoot(
    LoadedSave source,
    Set<String> selectedPaths, {
    LoadedSave? template,
  }) => _steam.build(
    source.onlyPaths(selectedPaths).records,
    template: template,
    arcadeMetadata: source.arcadeMetadata,
  );

  /// Writes [json] over the Neo Dimension save at [rootPath] after backing it
  /// up. Returns the backup's path. The game must be closed.
  Future<String> installSteamRoot(String rootPath, String json) async {
    if (!File(rootPath).existsSync()) {
      throw SaveException('There is no Neo Dimension save at $rootPath.');
    }
    final String backup = await FileOperations.backupFile(rootPath);
    await FileOperations.writeText(rootPath, json);
    return backup;
  }

  // ---------------------------------------------------------------------------
  // Neo Dimension -> Apple Arcade
  // ---------------------------------------------------------------------------

  /// Overlays [incoming] onto [existing] by path: matching slots are
  /// replaced in place, new ones are appended, and untouched slots stay.
  static List<SaveRecord> mergeIntoArcade(
    List<SaveRecord> existing,
    List<SaveRecord> incoming,
  ) {
    final Map<String, SaveRecord> replacements = <String, SaveRecord>{
      for (final SaveRecord record in incoming) record.path: record,
    };
    final List<SaveRecord> merged = <SaveRecord>[
      for (final SaveRecord record in existing) replacements.remove(record.path) ?? record,
    ];
    // Whatever is left in the map was not in the existing save.
    return merged..addAll(replacements.values);
  }

  /// Writes [incoming] straight into the database in [saveFolder].
  ///
  /// Simple, but only safe when iCloud will not overwrite it: a write from
  /// outside the game leaves no Core Data history, so iCloud never uploads it
  /// and may replace it with the cloud copy on next launch. The guided
  /// procedure ([GuidedMacInsertion]) avoids that.
  Future<DirectWriteResult> writeIntoArcadeFolder({
    required String saveFolder,
    required List<SaveRecord> incoming,
    required String backupRoot,
  }) async {
    final String? database = ArcadeDatabase.databaseIn(Directory(saveFolder));
    if (database == null) {
      throw _needsOwnSave(saveFolder);
    }
    if (await GameProcess.check() == GameRunState.running) {
      throw const SaveException('Quit FANTASIAN first, then try again.');
    }
    final LoadedSave current = await ArcadeDatabase.load(database);
    final String backup = await FileOperations.backupFolder(saveFolder, backupRoot: backupRoot);
    await ArcadeDatabase.writeRecords(database, mergeIntoArcade(current.records, incoming));
    final LoadedSave after = await ArcadeDatabase.load(database);
    _ensureContains(after, incoming);
    return DirectWriteResult(backupPath: backup, after: after);
  }

  /// Builds a zip of a FANTASIAN save folder: the database in [targetPaths]
  /// (a zip, folder or loose files from the destination device) with
  /// [incoming] merged in. For players who restore files by hand.
  Future<Uint8List> buildPatchedArcadeZip({
    required List<String> targetPaths,
    required List<SaveRecord> incoming,
  }) async {
    final StagedArcadeFolder staged = await _loader.stageArcade(targetPaths);
    try {
      final LoadedSave current = await ArcadeDatabase.load(staged.databasePath);
      await ArcadeDatabase.writeRecords(
        staged.databasePath,
        mergeIntoArcade(current.records, incoming),
      );
      _ensureContains(await ArcadeDatabase.load(staged.databasePath), incoming);

      final Archive archive = Archive();
      for (final File file in ArcadeDatabase.saveFiles(staged.databasePath)) {
        archive.addFile(
          ArchiveFile.bytes('FANTASIAN/${p.basename(file.path)}', await file.readAsBytes()),
        );
      }
      return ZipEncoder().encodeBytes(archive);
    } finally {
      await staged.dispose();
    }
  }

  /// Throws unless every record in [expected] reads back unchanged in [save].
  static void _ensureContains(LoadedSave save, List<SaveRecord> expected) {
    final Map<String, String> got = <String, String>{
      for (final SaveRecord record in save.records) record.path: record.plaintext,
    };
    for (final SaveRecord record in expected) {
      if (got[record.path] != record.plaintext) {
        throw SaveException(
          '${record.fileLabel} did not read back the same after writing.',
          hint: 'Restore the backup before playing.',
        );
      }
    }
  }

  /// The error for a Mac that has never saved.
  static SaveException _needsOwnSave(String folder) => SaveException(
    'There is no FANTASIAN save in $folder.',
    hint: 'Start FANTASIAN on this Mac, let it save once, quit, and try again. '
        'The game needs a database of its own to receive the save.',
  );
}

/// The steps of the guided, iCloud-safe insert, in order.
enum GuidedStep {
  /// Nothing done yet.
  ready,

  /// Backups taken and the converted database staged. Next: open the game.
  prepared,

  /// The converted database is in place. Next: load the slot in game.
  swappedIn,

  /// This Mac's own database is back. Next: save in game.
  swappedBack,

  /// Finished.
  done,
}

/// Inserts a save into the Apple Arcade game on this Mac through the running
/// game itself, so that iCloud keeps it.
///
/// FANTASIAN mirrors saves to iCloud through Core Data, and iCloud only
/// uploads changes recorded in Core Data's history tables. A file written from
/// outside the game has no history and is silently replaced by the cloud copy.
/// So, following the procedure proven by Fantasian-Save-Transfer:
///
/// 1. [prepare]: back up the save folder, keep a copy of this Mac's own
///    database, and stage a copy with the new slots merged in.
/// 2. Player starts the game and stays on the main menu.
/// 3. [swapIn]: replace the database files with the staged ones.
/// 4. Player opens Load and loads the slot (progress is now in memory).
/// 5. [swapBack]: put this Mac's own database back underneath the game.
/// 6. Player saves in game; that save is recorded properly and synced.
final class GuidedMacInsertion {
  /// Creates a procedure that inserts [incoming] into [saveFolder], keeping
  /// backups under [backupRoot].
  GuidedMacInsertion({
    required this.saveFolder,
    required this.incoming,
    required this.backupRoot,
  });

  /// The game's save folder on this Mac.
  final String saveFolder;

  /// The slots to bring in.
  final List<SaveRecord> incoming;

  /// Folder that receives the timestamped backup.
  final String backupRoot;

  GuidedStep _step = GuidedStep.ready;
  String? _backupPath;
  Directory? _workDir;

  /// The last completed step.
  GuidedStep get step => _step;

  /// Where the full backup of the save folder went, once [prepare] ran.
  String? get backupPath => _backupPath;

  String get _ownCopy => p.join(_workDir!.path, 'own');
  String get _stagedCopy => p.join(_workDir!.path, 'staged');

  /// Step 1. Requires the game to be closed so the files are consistent.
  Future<LoadedSave> prepare() async {
    _expect(GuidedStep.ready);
    final String? database = ArcadeDatabase.databaseIn(Directory(saveFolder));
    if (database == null) {
      throw SaveTransfer._needsOwnSave(saveFolder);
    }
    if (await GameProcess.check() == GameRunState.running) {
      throw const SaveException('Quit FANTASIAN before starting, then try again.');
    }
    _backupPath = await FileOperations.backupFolder(saveFolder, backupRoot: backupRoot);
    _workDir = await Directory.systemTemp.createTemp('fantasian_guided_');

    await FileOperations.copySaveFiles(saveFolder, _ownCopy);
    await FileOperations.copySaveFiles(saveFolder, _stagedCopy);
    final String stagedDb = p.join(_stagedCopy, ArcadeConstants.databaseFileName);
    final LoadedSave own = await ArcadeDatabase.load(stagedDb);
    await ArcadeDatabase.writeRecords(stagedDb, SaveTransfer.mergeIntoArcade(own.records, incoming));
    final LoadedSave staged = await ArcadeDatabase.load(stagedDb);
    SaveTransfer._ensureContains(staged, incoming);

    _step = GuidedStep.prepared;
    return staged;
  }

  /// Step 3. The game must be running (on its main menu).
  Future<LoadedSave> swapIn() async {
    _expect(GuidedStep.prepared);
    await _requireRunning('before the swap');
    await FileOperations.replaceSaveFiles(
      sourceFolder: _stagedCopy,
      destinationFolder: saveFolder,
    );
    _step = GuidedStep.swappedIn;
    return _readSaveFolder();
  }

  /// Step 5. The player has loaded the slot; put this Mac's own files back.
  Future<LoadedSave> swapBack() async {
    _expect(GuidedStep.swappedIn);
    await _requireRunning('after loading');
    await FileOperations.replaceSaveFiles(sourceFolder: _ownCopy, destinationFolder: saveFolder);
    _step = GuidedStep.swappedBack;
    return _readSaveFolder();
  }

  /// Step 6 confirmed by the player. Returns what is on disk now and cleans up.
  Future<LoadedSave> finish() async {
    _expect(GuidedStep.swappedBack);
    final LoadedSave now = await _readSaveFolder();
    _step = GuidedStep.done;
    await _cleanUp();
    return now;
  }

  /// Abandons the procedure. If this Mac's own files were swapped out, they
  /// are put back. Safe to call at any step.
  Future<void> cancel() async {
    if (_step == GuidedStep.swappedIn && _workDir != null) {
      await FileOperations.replaceSaveFiles(sourceFolder: _ownCopy, destinationFolder: saveFolder);
    }
    _step = GuidedStep.done;
    await _cleanUp();
  }

  Future<LoadedSave> _readSaveFolder() =>
      ArcadeDatabase.load(p.join(saveFolder, ArcadeConstants.databaseFileName));

  Future<void> _requireRunning(String when) async {
    if (await GameProcess.check() == GameRunState.notRunning) {
      throw SaveException(
        'FANTASIAN is not running ($when).',
        hint: 'The loaded progress only lives inside the running game. Start it '
            'and stay on the main menu, then press the button again.',
      );
    }
  }

  void _expect(GuidedStep expected) {
    if (_step != expected) {
      throw StateError('Guided insert is at $_step, expected $expected.');
    }
  }

  Future<void> _cleanUp() async {
    final Directory? work = _workDir;
    _workDir = null;
    if (work != null && work.existsSync()) {
      await work.delete(recursive: true);
    }
  }
}
