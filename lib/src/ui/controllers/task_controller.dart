/// Shared plumbing for the screen controllers: a busy flag, the last error and
/// the last result message.
library;

import 'package:flutter/foundation.dart';

import '../widgets/section_card.dart';

/// A message shown after an operation finishes.
@immutable
final class ResultMessage {
  /// Creates a message.
  const ResultMessage(this.tone, this.message, {this.detail});

  /// Colour and icon of the banner.
  final MessageTone tone;

  /// Main line.
  final String message;

  /// Optional extra lines (paths, next steps).
  final String? detail;
}

/// Base class for controllers that run one asynchronous task at a time.
abstract class TaskController extends ChangeNotifier {
  bool _busy = false;
  Object? _error;
  ResultMessage? _result;
  bool _disposed = false;

  /// Whether a task is running; the UI disables its buttons meanwhile.
  bool get busy => _busy;

  /// The error from the last task, if it failed.
  Object? get error => _error;

  /// The message from the last task, if it reported one.
  ResultMessage? get result => _result;

  /// Clears the error and result banners.
  void clearMessages() {
    _error = null;
    _result = null;
    notifyListeners();
  }

  /// Sets the result banner. For use inside [runTask].
  @protected
  void report(ResultMessage message) => _result = message;

  /// Shows [error] for a failure that happened outside [runTask], such as
  /// while preparing data for a native dialog.
  void showError(Object error) {
    _error = error;
    _result = null;
    notifyListeners();
  }

  /// Runs [task] with the busy flag set, capturing any error for display.
  /// Returns `true` when the task completed without throwing.
  @protected
  Future<bool> runTask(Future<void> Function() task) async {
    if (_busy) {
      return false;
    }
    _busy = true;
    _error = null;
    _result = null;
    notifyListeners();
    try {
      await task();
      return true;
    } on Object catch (error, stack) {
      _error = error;
      // Unexpected errors are bugs; keep the stack trace in the debug log.
      debugPrint('Task failed: $error\n$stack');
      return false;
    } finally {
      _busy = false;
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
