/// State and actions of the Insert screen (Neo Dimension -> Apple Arcade).
library;

import 'dart:typed_data';

import '../../core/save_exception.dart';
import '../../core/save_loader.dart';
import '../../core/save_locations.dart';
import '../../core/save_models.dart';
import '../../core/save_transfer.dart';
import '../widgets/section_card.dart';
import 'task_controller.dart';

/// How the save goes into the Mac.
enum InsertMode {
  /// Through the running game, so iCloud keeps it. Recommended.
  guided,

  /// Written straight into the database. Only sticks when iCloud does not
  /// replace it (iCloud off for the game, or offline).
  direct,
}

/// Drives the Insert screen.
class InsertController extends TaskController {
  /// Creates the controller with injectable services (for tests).
  InsertController({SaveLoader? loader, SaveLocations? locations, SaveTransfer? transfer})
    : _loader = loader ?? SaveLoader(),
      _locations = locations ?? SaveLocations(),
      _transfer = transfer ?? SaveTransfer();

  final SaveLoader _loader;
  final SaveLocations _locations;
  final SaveTransfer _transfer;

  LoadedSave? _source;
  final Set<String> _selected = <String>{};
  List<String> _steamRoots = const <String>[];
  String? _macFolder;
  LoadedSave? _macSave;
  InsertMode _mode = InsertMode.guided;
  GuidedMacInsertion? _guided;
  LoadedSave? _onDisk;

  /// The loaded Neo Dimension save.
  LoadedSave? get source => _source;

  /// Paths of the slots to bring in.
  Set<String> get selected => Set<String>.unmodifiable(_selected);

  /// Neo Dimension saves found on this machine (Windows / Linux).
  List<String> get steamRoots => _steamRoots;

  /// Whether this platform can write into the Apple Arcade game directly.
  bool get isMac => _locations.isMac;

  /// This Mac's save folder, if the game has saved here before.
  String? get macFolder => _macFolder;

  /// What is currently in this Mac's save, for the "will replace" chips.
  LoadedSave? get macSave => _macSave;

  /// Where the Mac save folder lives, for help text.
  String get macFolderHint => _locations.macSaveFolderHint();

  /// Where backups go.
  String get backupRoot => _locations.backupRoot();

  /// The chosen insert method.
  InsertMode get mode => _mode;

  /// The running guided procedure, if one was started.
  GuidedMacInsertion? get guided => _guided;

  /// What the last guided step left on disk, for display.
  LoadedSave? get onDisk => _onDisk;

  /// Whether step 2 can start.
  bool get hasSelection => _source != null && _selected.isNotEmpty;

  /// Slots on the Mac that the insert will overwrite.
  Set<String> get willReplace => <String>{
    for (final SaveRecord record in _macSave?.records ?? const <SaveRecord>[])
      if (_selected.contains(record.path)) record.path,
  };

  List<SaveRecord> get _incoming => _source?.onlyPaths(_selected).records ?? const <SaveRecord>[];

  /// Looks for saves on this machine. Call once when the screen opens.
  Future<void> discover() => runTask(() async {
    if (_locations.canHostSteamSave) {
      _steamRoots = await _locations.steamRootFiles();
    }
    await _refreshMacSave();
  });

  /// Step 1: loads a Neo Dimension (or FantasianSGE 0.1) `root.json`.
  Future<void> loadSteam(String path) => runTask(() async {
    _setSource(await _loader.loadSteamFile(path));
  });

  /// Step 1 from picked files.
  Future<void> loadFiles(List<String> paths) => runTask(() async {
    _setSource(await _loader.loadFiles(paths));
  });

  /// Ticks or unticks one slot.
  void toggle(String path) {
    if (_guided != null) {
      return; // The selection is fixed while a guided insert runs.
    }
    _selected.contains(path) ? _selected.remove(path) : _selected.add(path);
    notifyListeners();
  }

  /// Chooses guided or direct insertion.
  void setMode(InsertMode mode) {
    if (_guided != null) {
      return;
    }
    _mode = mode;
    notifyListeners();
  }

  /// Starts the guided procedure: backs up and stages the converted save.
  Future<void> startGuided() => runTask(() async {
    final String folder = _requireMacFolder();
    final GuidedMacInsertion procedure = GuidedMacInsertion(
      saveFolder: folder,
      incoming: _incoming,
      backupRoot: backupRoot,
      gameRunCheck: _transfer.gameRunCheck,
    );
    _onDisk = await procedure.prepare();
    _guided = procedure;
  });

  /// Runs the next tool step of the guided procedure, after the player has
  /// done what the current step asked in the game.
  Future<void> advanceGuided() => runTask(() async {
    final GuidedMacInsertion? procedure = _guided;
    if (procedure == null) {
      return;
    }
    switch (procedure.step) {
      case GuidedStep.prepared:
        _onDisk = await procedure.swapIn();
      case GuidedStep.swappedIn:
        _onDisk = await procedure.swapBack();
      case GuidedStep.swappedBack:
        _onDisk = await procedure.finish();
        report(
          ResultMessage(
            MessageTone.success,
            'Done. The save now belongs to this Mac.',
            detail:
                'Quit and relaunch FANTASIAN to check. If it asks "Confirm Save Data", '
                'pick the newest copy. iCloud will carry it to your iPhone or iPad.\n'
                'Backup: ${procedure.backupPath}',
          ),
        );
        _guided = null;
        await _refreshMacSave();
      case GuidedStep.ready || GuidedStep.done:
        break;
    }
  });

  /// Abandons the guided procedure, restoring this Mac's files if needed.
  Future<void> cancelGuided() => runTask(() async {
    final GuidedMacInsertion? procedure = _guided;
    _guided = null;
    _onDisk = null;
    if (procedure != null) {
      await procedure.cancel();
      report(
        ResultMessage(
          MessageTone.info,
          'Stopped. This Mac\'s own save files are in place.',
          detail: 'A full backup is at ${procedure.backupPath}',
        ),
      );
    }
    await _refreshMacSave();
  });

  /// Writes the selected slots straight into this Mac's database.
  Future<void> writeDirect() => runTask(() async {
    final DirectWriteResult result = await _transfer.writeIntoArcadeFolder(
      saveFolder: _requireMacFolder(),
      incoming: _incoming,
      backupRoot: backupRoot,
    );
    _macSave = result.after;
    report(
      ResultMessage(
        MessageTone.success,
        'Written into this Mac\'s save.',
        detail:
            'Start FANTASIAN and load the slot. If iCloud is on for the game it may '
            'replace this with the cloud copy; use the guided method in that case.\n'
            'Backup: ${result.backupPath}',
      ),
    );
  });

  /// Builds a zip of the target device's save folder with the selected slots
  /// merged in. [targetPaths] are the picked zip, folder or database files.
  Future<Uint8List?> buildPatchedZip(List<String> targetPaths) async {
    Uint8List? bytes;
    await runTask(() async {
      bytes = await _transfer.buildPatchedArcadeZip(targetPaths: targetPaths, incoming: _incoming);
    });
    return bytes;
  }

  /// Reports where the patched zip was saved.
  void reportZipSaved(String path) {
    report(
      ResultMessage(
        MessageTone.success,
        'Saved the patched FANTASIAN folder.',
        detail:
            '$path\n\nWith the game closed on the target device, replace the three '
            'SaveDataEntity.sqlite files in its FANTASIAN folder with these.',
      ),
    );
    notifyListeners();
  }

  void _setSource(LoadedSave save) {
    if (save.origin == SaveOrigin.appleArcade) {
      throw const SaveException(
        'That is already an Apple Arcade save.',
        hint: 'To bring it to Steam, use the Extract tab.',
      );
    }
    _source = save;
    _selected
      ..clear()
      ..addAll(save.records.map((SaveRecord record) => record.path));
  }

  String _requireMacFolder() {
    final String? folder = _macFolder;
    if (folder == null) {
      throw SaveException(
        'There is no FANTASIAN save on this Mac yet.',
        hint: 'Start FANTASIAN, let it save once, quit, and try again.\n'
            'Expected at: $macFolderHint',
      );
    }
    return folder;
  }

  /// Re-reads this Mac's save folder; missing or unreadable means "none".
  Future<void> _refreshMacSave() async {
    _macFolder = _locations.macSaveFolder();
    final String? folder = _macFolder;
    if (folder == null) {
      _macSave = null;
      return;
    }
    try {
      _macSave = await _loader.loadFolder(folder);
    } on SaveException {
      _macSave = null;
    }
  }
}
