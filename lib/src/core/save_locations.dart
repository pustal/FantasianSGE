/// Finds the game's save locations on the machine the app is running on.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'constants.dart';

/// Looks up where each release keeps its saves on this computer.
///
/// Everything here is best-effort: a location that cannot be found returns
/// `null` or an empty list, and the UI falls back to a file picker.
final class SaveLocations {
  /// Creates a locator. [environment] and [platform] can be overridden in
  /// tests; they default to the real process environment and OS.
  SaveLocations({Map<String, String>? environment, String? platform})
    : _env = environment ?? Platform.environment,
      _platform = platform ?? Platform.operatingSystem;

  final Map<String, String> _env;
  final String _platform;

  /// Whether the app runs on macOS, the only place the Apple Arcade save can
  /// be read and written directly.
  bool get isMac => _platform == 'macos';

  /// Whether this OS can run the Steam release (Windows, or Linux / Steam
  /// Deck through Proton), so its save folder may exist here.
  bool get canHostSteamSave => _platform == 'windows' || _platform == 'linux';

  /// The Apple Arcade save folder on this Mac, if it exists.
  String? macSaveFolder() {
    final String? home = _env['HOME'];
    if (!isMac || home == null) {
      return null;
    }
    final String folder = p.joinAll(<String>[home, ...ArcadeConstants.macSaveFolderSegments]);
    return Directory(folder).existsSync() ? folder : null;
  }

  /// Where this app keeps backups of the Mac save folder:
  /// `~/Documents/FantasianSGE Backups`. Kept outside the game's container
  /// so the player can find them in Finder.
  String backupRoot() {
    final String home = _env['HOME'] ?? _env['USERPROFILE'] ?? Directory.systemTemp.path;
    return p.join(home, 'Documents', 'FantasianSGE Backups');
  }

  /// The path the Mac save folder would have, whether or not it exists. Shown
  /// in help text.
  String macSaveFolderHint() =>
      p.joinAll(<String>['~', ...ArcadeConstants.macSaveFolderSegments]);

  /// Every Neo Dimension `root.json` on this machine, most recently modified
  /// first. Several are possible when more than one Steam account played.
  Future<List<String>> steamRootFiles() async {
    final List<File> found = <File>[];
    for (final String documents in await _documentsCandidates()) {
      final Directory steamFolder = Directory(
        p.join(documents, 'My Games', SteamConstants.gameFolderName, 'Steam'),
      );
      if (!steamFolder.existsSync()) {
        continue;
      }
      for (final FileSystemEntity account in steamFolder.listSync()) {
        final File root = File(p.join(account.path, '_data', SteamConstants.rootFileName));
        if (account is Directory && root.existsSync()) {
          found.add(root);
        }
      }
    }
    found.sort(
      (File a, File b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
    );
    return <String>[for (final File file in found) file.path];
  }

  /// Folders that may play the role of "Documents" for the game: the real
  /// Windows Documents folder (which OneDrive often redirects), the usual
  /// fallbacks, and the Proton prefix used on Linux / Steam Deck.
  Future<List<String>> _documentsCandidates() async {
    final List<String> out = <String>[];
    if (_platform == 'windows') {
      final String? registered = await _windowsDocumentsFromRegistry();
      if (registered != null) {
        out.add(registered);
      }
      for (final String? base in <String?>[
        _env['USERPROFILE'],
        _env['OneDrive'],
        _env['OneDriveConsumer'],
      ]) {
        if (base != null) {
          out.add(p.join(base, 'Documents'));
        }
      }
      if (_env['USERPROFILE'] case final String profile) {
        out.add(p.join(profile, 'OneDrive', 'Documents'));
      }
    }
    if (_platform == 'linux') {
      final String? home = _env['HOME'];
      if (home != null) {
        for (final String steam in <String>[
          p.join(home, '.local', 'share', 'Steam'),
          p.join(home, '.steam', 'steam'),
          p.join(home, '.var', 'app', 'com.valvesoftware.Steam', '.local', 'share', 'Steam'),
        ]) {
          out.add(
            p.join(steam, 'steamapps', 'compatdata', SteamConstants.appId, 'pfx', 'drive_c',
                'users', 'steamuser', 'Documents'),
          );
        }
      }
    }
    return out.toSet().toList();
  }

  /// Asks Windows where the Documents folder really is, which accounts for
  /// OneDrive redirection. Uses `reg.exe` so no native plugin is needed.
  Future<String?> _windowsDocumentsFromRegistry() async {
    try {
      final ProcessResult result = await Process.run('reg', <String>[
        'query',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders',
        '/v',
        'Personal',
      ]);
      final Object? stdout = result.stdout;
      if (result.exitCode != 0 || stdout is! String) {
        return null;
      }
      // Output line: "    Personal    REG_SZ    C:\Users\me\Documents"
      final RegExpMatch? match = RegExp(r'Personal\s+REG_\w+\s+(.+)').firstMatch(stdout);
      final String? value = match?.group(1)?.trim();
      return value == null || value.isEmpty ? null : _expandWindowsVariables(value);
    } on ProcessException {
      return null;
    }
  }

  /// Expands `%VARIABLE%` references using the process environment.
  String _expandWindowsVariables(String value) => value.replaceAllMapped(
    RegExp('%([^%]+)%'),
    (Match match) => _env[match.group(1)] ?? match.group(0)!,
  );
}
