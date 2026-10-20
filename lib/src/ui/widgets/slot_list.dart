/// Shows the slots of a save, optionally with checkboxes to pick some.
library;

import 'package:flutter/material.dart';

import '../../core/save_models.dart';

/// A list of save slots with their date, play time, gil and location.
class SlotList extends StatelessWidget {
  /// Creates the list. When [selected] and [onToggle] are given, each row
  /// gets a checkbox.
  const SlotList({
    required this.records,
    this.selected,
    this.onToggle,
    this.highlight = const <String>{},
    this.highlightLabel,
    super.key,
  });

  /// The slots to show. They are displayed autosave first, then by number.
  final List<SaveRecord> records;

  /// Paths of the ticked slots, when the list is selectable.
  final Set<String>? selected;

  /// Called with a slot's path when its checkbox is toggled.
  final ValueChanged<String>? onToggle;

  /// Paths to flag with [highlightLabel] (e.g. "will be replaced").
  final Set<String> highlight;

  /// The chip text shown on highlighted rows.
  final String? highlightLabel;

  @override
  Widget build(BuildContext context) {
    final List<SaveRecord> ordered = records.toList()
      ..sort((SaveRecord a, SaveRecord b) =>
          (a.slotNumber ?? 999).compareTo(b.slotNumber ?? 999));
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < ordered.length; i++) ...<Widget>[
            if (i > 0) const Divider(height: 1),
            _SlotRow(
              record: ordered[i],
              selected: selected?.contains(ordered[i].path),
              onToggle: onToggle,
              highlightLabel: highlight.contains(ordered[i].path) ? highlightLabel : null,
            ),
          ],
        ],
      ),
    );
  }
}

/// One row of the [SlotList].
class _SlotRow extends StatelessWidget {
  const _SlotRow({
    required this.record,
    required this.selected,
    required this.onToggle,
    required this.highlightLabel,
  });

  final SaveRecord record;
  final bool? selected;
  final ValueChanged<String>? onToggle;
  final String? highlightLabel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final SlotSummary summary = record.summarise();
    final bool selectable = selected != null && onToggle != null;

    final List<String> facts = <String>[
      if (summary.savedAt != null) summary.savedAt!,
      if (summary.playTime != null) formatPlayTime(summary.playTime!),
      if (summary.money != null) '${formatThousands(summary.money!)} G',
      if (summary.mapId != null) summary.mapId!,
    ];

    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: <Widget>[
          if (selectable)
            Checkbox(value: selected, onChanged: (_) => onToggle!(record.path))
          else
            Icon(Icons.diamond_outlined, color: scheme.secondary, size: 20),
          const SizedBox(width: 8),
          SizedBox(
            width: 104,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(record.gameLabel, style: theme.textTheme.titleSmall),
                Text(
                  record.fileLabel,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Expanded(
            child: Text(
              summary.problem != null ? 'Could not read this slot' : facts.join('  ·  '),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: summary.problem != null ? scheme.error : null,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (highlightLabel != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Chip(
                label: Text(highlightLabel!),
                visualDensity: VisualDensity.compact,
                backgroundColor: scheme.tertiary.withValues(alpha: 0.18),
                side: BorderSide.none,
              ),
            ),
        ],
      ),
    );

    return selectable
        ? InkWell(onTap: () => onToggle!(record.path), child: content)
        : content;
  }
}

/// Formats play time the way the game's Load screen does, e.g. `42h 07m`.
String formatPlayTime(Duration duration) {
  final int hours = duration.inHours;
  final int minutes = duration.inMinutes.remainder(60);
  return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
}

/// Formats [value] with thousands separators, e.g. `88,120`.
String formatThousands(int value) {
  final String digits = value.abs().toString();
  final StringBuffer out = StringBuffer(value < 0 ? '-' : '');
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      out.write(',');
    }
    out.write(digits[i]);
  }
  return out.toString();
}
