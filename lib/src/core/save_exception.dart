/// The single error type the save layer throws for problems a player can act
/// on (missing files, a database with no save in it, a wrong file picked...).
///
/// The UI shows [message] as-is and [hint], when present, underneath it.
/// Anything else that escapes the core layer is a bug and is reported as such.
final class SaveException implements Exception {
  /// Creates an error with a player-facing [message] and an optional [hint].
  const SaveException(this.message, {this.hint});

  /// What went wrong, in plain words.
  final String message;

  /// What the player can do about it, if there is something.
  final String? hint;

  @override
  String toString() => hint == null ? message : '$message\n$hint';
}
