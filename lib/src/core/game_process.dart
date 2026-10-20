/// Detects whether the Apple Arcade game is running on this Mac.
library;

import 'dart:io';

import 'constants.dart';

/// Whether FANTASIAN is running, as far as can be told.
enum GameRunState {
  /// The game process was found.
  running,

  /// No game process was found.
  notRunning,

  /// The check could not be made (not macOS, or `pgrep` failed).
  unknown,
}

/// Process checks used by the insert workflows.
abstract final class GameProcess {
  /// Looks for the game's process with `pgrep`, matching the app bundle path
  /// so this app (FantasianSGE.app) never counts as the game.
  static Future<GameRunState> check() async {
    if (!Platform.isMacOS) {
      return GameRunState.unknown;
    }
    try {
      final ProcessResult result = await Process.run('pgrep', <String>[
        '-f',
        ArcadeConstants.macProcessMarker,
      ]);
      final Object? stdout = result.stdout;
      if (stdout is! String) {
        return GameRunState.unknown;
      }
      final Iterable<int> others = stdout
          .split(RegExp(r'\s+'))
          .map(int.tryParse)
          .whereType<int>()
          .where((int id) => id != pid);
      return others.isEmpty ? GameRunState.notRunning : GameRunState.running;
    } on ProcessException {
      return GameRunState.unknown;
    }
  }
}
