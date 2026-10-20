/// Building blocks for the step-by-step screens.
library;

import 'package:flutter/material.dart';

import '../../core/save_exception.dart';

/// A numbered step: a gold medallion with [step], a title, an optional
/// description and the step's content.
class SectionCard extends StatelessWidget {
  /// Creates a step card.
  const SectionCard({
    required this.step,
    required this.title,
    required this.child,
    this.description,
    this.enabled = true,
    super.key,
  });

  /// The step's number, shown as a Roman numeral in the medallion.
  final int step;

  /// The step's heading.
  final String title;

  /// One or two sentences under the heading.
  final String? description;

  /// The step's controls.
  final Widget child;

  /// Dims the card when an earlier step is not done yet.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled ? 1 : 0.45,
      child: IgnorePointer(
        ignoring: !enabled,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    _Medallion(step: step),
                    const SizedBox(width: 14),
                    Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
                  ],
                ),
                if (description != null) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(
                    description!,
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 16),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The gold numbered circle at the start of a [SectionCard].
class _Medallion extends StatelessWidget {
  const _Medallion({required this.step});

  final int step;

  static const List<String> _numerals = <String>['I', 'II', 'III', 'IV', 'V', 'VI'];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFFFBE3A0), Color(0xFFE0B456), Color(0xFF9C6B22)],
        ),
        border: Border.all(color: const Color(0xFF6E4A14), width: 1.5),
      ),
      child: Text(
        step <= _numerals.length ? _numerals[step - 1] : '$step',
        style: theme.textTheme.titleSmall?.copyWith(
          fontFamily: 'Cinzel',
          color: const Color(0xFF2E1F02),
          fontWeight: FontWeight.w700,
        ),
        semanticsLabel: 'Step $step',
      ),
    );
  }
}

/// The tone of a [MessageBanner].
enum MessageTone {
  /// Neutral information.
  info,

  /// Something worked.
  success,

  /// Something needs care.
  warning,

  /// Something failed.
  error,
}

/// A coloured panel for results, warnings and errors.
class MessageBanner extends StatelessWidget {
  /// Creates a banner.
  const MessageBanner({
    required this.tone,
    required this.message,
    this.detail,
    super.key,
  });

  /// Builds an error banner from any error object, showing a [SaveException]'s
  /// message and hint and anything else as an unexpected error.
  factory MessageBanner.fromError(Object error) => switch (error) {
    SaveException(:final String message, :final String? hint) =>
      MessageBanner(tone: MessageTone.error, message: message, detail: hint),
    _ => MessageBanner(
      tone: MessageTone.error,
      message: 'Something unexpected went wrong.',
      detail: '$error',
    ),
  };

  /// The tone, which picks the colours and icon.
  final MessageTone tone;

  /// The main line.
  final String message;

  /// Optional extra lines.
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final (Color background, Color foreground, IconData icon) = switch (tone) {
      MessageTone.info => (scheme.secondaryContainer, scheme.onSecondaryContainer, Icons.info_outline),
      MessageTone.success => (scheme.primaryContainer, scheme.onPrimaryContainer, Icons.auto_awesome),
      MessageTone.warning => (scheme.tertiary.withValues(alpha: 0.18), scheme.onSurface, Icons.warning_amber),
      MessageTone.error => (scheme.errorContainer, scheme.onErrorContainer, Icons.error_outline),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: foreground, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: SelectionArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(message, style: theme.textTheme.titleSmall?.copyWith(color: foreground)),
                  if (detail != null) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(detail!, style: theme.textTheme.bodySmall?.copyWith(color: foreground)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Wraps buttons so they flow onto new lines on narrow screens.
class ButtonRow extends StatelessWidget {
  /// Creates the row.
  const ButtonRow({required this.children, super.key});

  /// The buttons.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      Wrap(spacing: 10, runSpacing: 10, children: children);
}
