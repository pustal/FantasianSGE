/// State and actions of the Extract screen (Apple Arcade -> Neo Dimension).
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../core/constants.dart';
import '../../core/save_exception.dart';
import '../../core/save_loader.dart';
import '../../core/save_locations.dart';
import '../../core/save_models.dart';
import '../../core/save_transfer.dart';
import '../../core/steam_root.dart';
import '../widgets/section_card.dart';
import 'task_controller.dart';

/// Drives the Extract screen.
class ExtractController extends TaskController {
  /// Creates the controller with injectable services (for tests).
  ExtractController({SaveLoader? loader, SaveLocations? locations, SaveTransfer? transfer})
    : _loader = loader ?? SaveLoader(),
      _locations = locations ?? SaveLocations(),
      _transfer = transfer ?? SaveTransfer();

  final SaveLoader _loader;
  final SaveLocations _locations;
  final SaveTransfer _transfer;

  LoadedSave? _source;
  final Set<String> _selected = <String>{};
  bool _merge = false;
  LoadedSave? _template;
  String? _templatePath;
  List<String> _steamRoots = const <String>[];
  String? _macFolder;

  /// The loaded Apple Arcade save, once step 1 is done.
  LoadedSave? get source => _source;

  /// Paths of the slots that will be exported.
  Set<String> get selected => Set<String>.unmodifiable(_selected);

  /// Whether to merge into an existing Neo Dimension save.
  bool get merge => _merge;

  /// The Neo Dimension save to merge into, when [merge] is on and one is loaded.
  LoadedSave? get template => _template;

  /// Where [template] came from.
  String? get templatePath => _templatePath;

  /// Neo Dimension saves found on this machine (Windows / Linux).
  List<String> get steamRoots => _steamRoots;

  /// This Mac's Apple Arcade save folder, if it exists.
  String? get macFolder => _macFolder;

  /// Where the Mac save folder lives, for help text.
  String get macFolderHint => _locations.macSaveFolderHint();

  /// Whether the "install into the game" action is possible.
  bool get canInstall => _merge && _template != null && _templatePath != null && _canWriteTemplate;

  bool get _canWriteTemplate => _steamRoots.contains(_templatePath);

  /// Whether step 3 can run.
  bool get readyToExport => _source != null && _selected.isNotEmpty && (!_merge || _template != null);

  /// Slots in the template that the export will overwrite.
  Set<String> get willReplace => <String>{
    for (final SaveRecord record in _template?.records ?? const <SaveRecord>[])
      if (_selected.contains(record.path)) record.path,
  };

  /// Looks for saves on this machine. Call once when the screen opens.
  Future<void> discover() async {
    _macFolder = _locations.macSaveFolder();
    if (_locations.canHostSteamSave) {
      _steamRoots = await _locations.steamRootFiles();
    }
    notifyListeners();
  }

  /// Step 1 from this Mac's own save folder.
  Future<void> loadMacSave() async {
    final String? folder = _macFolder;
    if (folder == null) {
      return;
    }
    await loadFolder(folder);
  }

  /// Step 1 from a picked folder.
  Future<void> loadFolder(String path) => runTask(() async {
    _setSource(await _loader.loadFolder(path));
  });

  /// Step 1 from picked files (zip, sqlite + sidecars, or a legacy root.json).
  Future<void> loadFiles(List<String> paths) => runTask(() async {
    _setSource(await _loader.loadFiles(paths));
  });

  /// Ticks or unticks one slot.
  void toggle(String path) {
    _selected.contains(path) ? _selected.remove(path) : _selected.add(path);
    notifyListeners();
  }

  /// Turns merging on or off. Turning it on picks the newest Neo Dimension
  /// save found on this machine, if any.
  Future<void> setMerge(bool value) async {
    _merge = value;
    _template = null;
    _templatePath = null;
    notifyListeners();
    if (value && _steamRoots.isNotEmpty) {
      await loadTemplate(_steamRoots.first);
    }
  }

  /// Loads the Neo Dimension save to merge into.
  Future<void> loadTemplate(String path) => runTask(() async {
    final LoadedSave save = await _loader.loadSteamFile(path);
    if (save.origin != SaveOrigin.neoDimension) {
      throw const SaveException(
        'That root.json is not a Neo Dimension save.',
        hint: 'Pick the root.json from the Neo Dimension save folder on your PC or Steam Deck.',
      );
    }
    _template = save;
    _templatePath = path;
  });

  /// Builds the `root.json` bytes for saving. Throws [SaveException] on
  /// invalid input.
  Uint8List buildRootJson() {
    final LoadedSave? source = _source;
    if (source == null) {
      throw const SaveException('Load an Apple Arcade save first.');
    }
    final SteamBuildResult built = _transfer.buildSteamRoot(
      source,
      _selected,
      template: _merge ? _template : null,
    );
    return Uint8List.fromList(utf8.encode(built.json));
  }

  /// Reports a successful "Save as" to [path].
  void reportSaved(String path) {
    final String where = _locations.canHostSteamSave
        ? 'Close the game, back up the root.json already there, and copy this one over it.'
        : 'Copy it to the PC or Steam Deck, close the game there, back up the existing '
              'root.json and replace it with this one.';
    report(
      ResultMessage(
        MessageTone.success,
        'Saved ${SteamConstants.rootFileName}',
        detail:
            '$path\n\n$where\n'
            r'Windows: Documents\My Games\FANTASIAN Neo Dimension\Steam\<steam id>\_data\'
            '\nSteam Deck: ~/.local/share/Steam/steamapps/compatdata/${SteamConstants.appId}/pfx/'
            'drive_c/users/steamuser/Documents/My Games/FANTASIAN Neo Dimension/Steam/<steam id>/_data/',
      ),
    );
    notifyListeners();
  }

  /// Writes the export straight into the merge target on this machine.
  Future<void> installIntoGame() => runTask(() async {
    final String? target = _templatePath;
    if (!canInstall || target == null) {
      throw const SaveException('Pick a Neo Dimension save on this computer to install into.');
    }
    final String json = utf8.decode(buildRootJson());
    final String backup = await _transfer.installSteamRoot(target, json);
    _template = await _loader.loadSteamFile(target);
    report(
      ResultMessage(
        MessageTone.success,
        'Installed into Neo Dimension',
        detail:
            'Start the game and load the slot to check it before playing on.\n'
            'Your previous save was backed up to:\n$backup',
      ),
    );
  });

  /// Replaces the source and ticks every slot.
  void _setSource(LoadedSave save) {
    if (save.origin == SaveOrigin.neoDimension) {
      throw const SaveException(
        'That is already a Neo Dimension save.',
        hint: 'To bring it to Apple Arcade, use the Insert tab.',
      );
    }
    _source = save;
    _selected
      ..clear()
      ..addAll(save.records.map((SaveRecord record) => record.path));
  }
}
