/// Fixed values shared by the whole app: links, file names, platform paths and
/// the Neo Dimension encryption parameters.
library;

/// Identity of the app itself.
abstract final class AppInfo {
  /// Display name.
  static const String name = 'FantasianSGE';

  /// Version shown on the About screen. Keep in sync with `pubspec.yaml`.
  static const String version = '1.0.0';
}

/// Links shown on the About screen.
abstract final class AppLinks {
  /// Source code of this project.
  static final Uri github = Uri.parse('https://github.com/pustal/FantasianSGE');

  /// The author's Ko-fi page.
  static final Uri kofi = Uri.parse('https://ko-fi.com/pustal');

  /// The Python tool whose research this app's Steam and guided-insert logic
  /// follows (GPL-3.0, same as this project).
  static final Uri saveTransfer =
      Uri.parse('https://github.com/RobThePCGuy/Fantasian-Save-Transfer');

  /// The Neo Dimension save editor that first documented the Steam format.
  static final Uri ndSaveEditor =
      Uri.parse('https://github.com/mathcodergamer/FantasianND-Save-Editor');
}

/// Names and locations used by the Apple Arcade release.
abstract final class ArcadeConstants {
  /// The Core Data store the game writes its saves into.
  static const String databaseFileName = 'SaveDataEntity.sqlite';

  /// SQLite sidecar suffixes. The live progress usually sits in the `-wal`
  /// file, so the three files must always travel together.
  static const List<String> sidecarSuffixes = <String>['-wal', '-shm'];

  /// The Core Data table holding one row per save container.
  static const String table = 'ZGAMEDATAENTITY';

  /// Path segments, relative to the user's home folder, of the save folder on
  /// macOS. The game is sandboxed, so this sits inside its container.
  static const List<String> macSaveFolderSegments = <String>[
    'Library',
    'Containers',
    'com.mistwalkercorp.fantasian',
    'Data',
    'Library',
    'Application Support',
    'FANTASIAN',
  ];

  /// Substring of the running game's executable path, used to tell whether the
  /// game is open. It deliberately does not match this app's own bundle.
  static const String macProcessMarker = 'FANTASIAN.app';

  /// Core Data stores dates as seconds since 2001-01-01 UTC. This is that
  /// instant expressed as seconds since the Unix epoch.
  static const int coreDataEpochOffsetSeconds = 978307200;
}

/// Names, locations and crypto parameters used by FANTASIAN Neo Dimension.
abstract final class SteamConstants {
  /// Steam application id of FANTASIAN Neo Dimension.
  static const String appId = '2844850';

  /// Folder the game creates under `Documents/My Games`.
  static const String gameFolderName = 'FANTASIAN Neo Dimension';

  /// The save file name inside `<steam id>/_data/`.
  static const String rootFileName = 'root.json';

  /// AES-128 key baked into the game (identical on every copy). Documented by
  /// FantasianND-Save-Editor.
  static const String aesKey = 'yrhWj8EiU83kXupm';

  /// AES-CBC initialisation vector baked into the game.
  static const String aesIv = 'Nq4G3pTQFLTCeiB7';

  /// Seconds between 0001-01-01 (the .NET `DateTime` epoch used by the
  /// game's `utcTick` field) and the Unix epoch.
  static const int dotNetEpochOffsetSeconds = 62135596800;

  /// .NET ticks are 100 ns long, so there are ten million per second.
  static const int ticksPerSecond = 10000000;
}
