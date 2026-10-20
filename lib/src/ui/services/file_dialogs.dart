/// A thin wrapper over the native file dialogs, so screens never talk to the
/// plugin directly and tests can substitute a fake.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Native open/save dialogs.
class FileDialogs {
  /// Creates the real implementation.
  const FileDialogs();

  /// Whether the platform can pick a whole folder. Desktop only: on iOS a
  /// folder pick hands back a security-scoped URL the app cannot simply walk,
  /// so players there pick files or a zip instead.
  bool get canPickFolders => Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  /// Lets the player pick one or more files and returns their local paths.
  /// On iOS the plugin copies picked files into the app's temporary folder,
  /// so the returned paths are always readable.
  Future<List<String>> pickFiles({required String title}) async {
    final List<PlatformFile> files = await FilePicker.pickFiles(dialogTitle: title);
    return <String>[
      for (final PlatformFile file in files)
        if (file.path case final String path) path,
    ];
  }

  /// Lets the player pick a folder; `null` when cancelled.
  Future<String?> pickFolder({required String title, String? initialDirectory}) =>
      FilePicker.getDirectoryPath(dialogTitle: title, initialDirectory: initialDirectory);

  /// Shows a save dialog for [bytes]. Returns where it was saved, or `null`
  /// when the player cancelled. On iOS this is the Files "Save to" sheet.
  Future<String?> saveBytes({
    required String title,
    required String fileName,
    required Uint8List bytes,
    String mimeType = 'application/octet-stream',
  }) async {
    final Uri? uri = await FilePicker.saveFile(
      dialogTitle: title,
      fileName: fileName,
      bytes: bytes,
      mimeType: mimeType,
    );
    if (uri == null) {
      return null;
    }
    return uri.scheme == 'file' ? uri.toFilePath() : uri.toString();
  }
}
