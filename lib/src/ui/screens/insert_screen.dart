/// The Insert tab: Neo Dimension `root.json` -> Apple Arcade.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/save_models.dart';
import '../../core/save_transfer.dart';
import '../controllers/insert_controller.dart';
import '../controllers/task_controller.dart';
import '../services/file_dialogs.dart';
import '../widgets/section_card.dart';
import '../widgets/slot_list.dart';
import 'page_frame.dart';

/// Lets the player bring a Steam save back into the Apple Arcade game.
class InsertScreen extends StatefulWidget {
  /// Creates the screen.
  const InsertScreen({this.dialogs = const FileDialogs(), this.controller, super.key});

  /// Native file dialogs (replaceable in tests).
  final FileDialogs dialogs;

  /// An externally owned controller (for tests and previews). When `null`
  /// the screen creates and disposes its own.
  final InsertController? controller;

  @override
  State<InsertScreen> createState() => _InsertScreenState();
}

class _InsertScreenState extends State<InsertScreen> {
  late final InsertController _controller = widget.controller ?? InsertController();

  /// Whether this state created [_controller] and must dispose it.
  bool get _ownsController => widget.controller == null;

  @override
  void initState() {
    super.initState();
    if (_ownsController) {
      _controller.discover();
    }
  }

  @override
  void dispose() {
    // Never leave this Mac's files swapped out if the window closes mid-way.
    if (_controller.guided != null) {
      _controller.cancelGuided();
    }
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  FileDialogs get _dialogs => widget.dialogs;

  Future<void> _pickSource() async {
    final List<String> paths = await _dialogs.pickFiles(title: 'Pick your Neo Dimension root.json');
    if (paths.isNotEmpty) {
      await _controller.loadFiles(paths);
    }
  }

  Future<void> _buildZip() async {
    final List<String> targets = await _dialogs.pickFiles(
      title: 'Pick the target device\'s FANTASIAN zip or SaveDataEntity.sqlite (+ -wal, -shm)',
    );
    if (targets.isEmpty) {
      return;
    }
    final Uint8List? bytes = await _controller.buildPatchedZip(targets);
    if (bytes == null) {
      return;
    }
    final String? path = await _dialogs.saveBytes(
      title: 'Save the patched FANTASIAN folder',
      fileName: 'FANTASIAN-patched.zip',
      bytes: bytes,
      mimeType: 'application/zip',
    );
    if (path != null) {
      _controller.reportZipSaved(path);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (BuildContext context, Widget? _) => PageFrame(
      title: 'Steam to Apple Arcade',
      intro:
          'Bring a FANTASIAN Neo Dimension save back to Apple Arcade. It goes in on '
          'a Mac, and iCloud then carries it to your iPhone and iPad.',
      children: <Widget>[
        _sourceStep(context),
        if (_controller.isMac) _macStep(context) else _elsewhereStep(context),
        if (_controller.busy) const LinearProgressIndicator(),
        if (_controller.error case final Object error) MessageBanner.fromError(error),
        if (_controller.result case final ResultMessage result)
          MessageBanner(tone: result.tone, message: result.message, detail: result.detail),
      ],
    ),
  );

  Widget _sourceStep(BuildContext context) {
    final LoadedSave? source = _controller.source;
    final bool locked = _controller.busy || _controller.guided != null;
    return SectionCard(
      step: 1,
      title: 'Find your Neo Dimension save',
      description:
          r'On Windows it is Documents\My Games\FANTASIAN Neo Dimension\Steam\<steam id>\_data\root.json. '
          'Copy it to this device, or pick it directly when the app runs on that PC.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ButtonRow(
            children: <Widget>[
              if (_controller.steamRoots.isNotEmpty)
                FilledButton.icon(
                  onPressed: locked ? null : () => _controller.loadSteam(_controller.steamRoots.first),
                  icon: const Icon(Icons.sports_esports_outlined),
                  label: const Text('Use this PC\'s save'),
                ),
              OutlinedButton.icon(
                onPressed: locked ? null : _pickSource,
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('Choose root.json…'),
              ),
            ],
          ),
          if (source != null) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              '${source.origin.label} · ${p.basename(source.sourceDescription)} · '
              '${_controller.selected.length} of ${source.records.length} slots selected',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 8),
            SlotList(
              records: source.records,
              selected: _controller.selected,
              onToggle: _controller.guided == null ? _controller.toggle : null,
              highlight: _controller.willReplace,
              highlightLabel: 'replaces Mac slot',
            ),
          ],
        ],
      ),
    );
  }

  Widget _macStep(BuildContext context) {
    final bool hasMacSave = _controller.macFolder != null;
    return SectionCard(
      step: 2,
      enabled: _controller.hasSelection,
      title: 'Put it into FANTASIAN on this Mac',
      description: hasMacSave
          ? 'Your Mac save folder is backed up to ${_controller.backupRoot} before anything changes.'
          : 'FANTASIAN has not saved on this Mac yet. Start the game, save once, quit, '
                'then come back: the game needs a database of its own.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SegmentedButton<InsertMode>(
            segments: const <ButtonSegment<InsertMode>>[
              ButtonSegment<InsertMode>(
                value: InsertMode.guided,
                icon: Icon(Icons.auto_awesome),
                label: Text('Guided (iCloud-safe)'),
              ),
              ButtonSegment<InsertMode>(
                value: InsertMode.direct,
                icon: Icon(Icons.bolt),
                label: Text('Direct write'),
              ),
            ],
            selected: <InsertMode>{_controller.mode},
            onSelectionChanged: _controller.guided != null
                ? null
                : (Set<InsertMode> value) => _controller.setMode(value.first),
          ),
          const SizedBox(height: 16),
          if (_controller.mode == InsertMode.guided)
            _GuidedPanel(controller: _controller)
          else
            _DirectPanel(controller: _controller),
        ],
      ),
    );
  }

  Widget _elsewhereStep(BuildContext context) => SectionCard(
    step: 2,
    enabled: _controller.hasSelection,
    title: 'Put it into Apple Arcade',
    description:
        'FANTASIAN syncs its saves through iCloud, and iCloud only keeps a save '
        'the game itself wrote. So the reliable way in is this app on a Mac with '
        'FANTASIAN installed (it is part of Apple Arcade there too): the guided '
        'insert lets the game load your Steam slot and save it, and iCloud then '
        'delivers it to this device. Apps on iOS cannot reach another game\'s files.',
    child: ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('Advanced: build a patched save folder'),
      subtitle: const Text('For restoring files by hand, with iCloud off for the game.'),
      childrenPadding: const EdgeInsets.only(bottom: 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Pick the destination device\'s own FANTASIAN folder as a zip (or its '
          'SaveDataEntity.sqlite with -wal and -shm). The selected slots are merged '
          'into it and you get a zip back to restore with the game closed.',
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _controller.busy || !_controller.hasSelection ? null : _buildZip,
          icon: const Icon(Icons.folder_zip_outlined),
          label: const Text('Choose target and build zip…'),
        ),
      ],
    ),
  );
}

/// The guided procedure: a checklist that alternates between what the app
/// does and what the player does in the game.
class _GuidedPanel extends StatelessWidget {
  const _GuidedPanel({required this.controller});

  final InsertController controller;

  @override
  Widget build(BuildContext context) {
    final GuidedStep step = controller.guided?.step ?? GuidedStep.ready;
    final bool busy = controller.busy;
    final bool canStart = controller.macFolder != null && controller.hasSelection && !busy;

    // The player's instructions for each stage, and the button that confirms
    // they did it.
    final List<(GuidedStep, String, String)> stages = <(GuidedStep, String, String)>[
      (GuidedStep.prepared, 'Start FANTASIAN and stay on the main menu.', 'Game is on the main menu'),
      (GuidedStep.swappedIn, 'Open Load, pick your Steam slot and let it load into the world. Do not quit.', 'Slot is loaded'),
      (GuidedStep.swappedBack, 'Save at a save point, in an empty slot if you have one. If the Load screen looked empty or old, ignore it.', 'I saved in game'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const MessageBanner(
          tone: MessageTone.info,
          message: 'Why guided?',
          detail:
              'iCloud only uploads saves the game itself made. Here the game loads '
              'your Steam slot from a temporary copy, this Mac\'s own files go back '
              'underneath, and your in-game save makes it stick on every device.',
        ),
        const SizedBox(height: 12),
        if (step == GuidedStep.ready)
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: canStart ? controller.startGuided : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Quit FANTASIAN, then start'),
            ),
          )
        else ...<Widget>[
          for (int i = 0; i < stages.length; i++)
            _StageTile(
              index: i + 1,
              text: stages[i].$2,
              state: step.index > stages[i].$1.index
                  ? _StageState.done
                  : step == stages[i].$1
                  ? _StageState.current
                  : _StageState.waiting,
              action: step == stages[i].$1
                  ? FilledButton(
                      onPressed: busy ? null : controller.advanceGuided,
                      child: Text(stages[i].$3),
                    )
                  : null,
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: busy ? null : controller.cancelGuided,
              icon: const Icon(Icons.undo),
              label: const Text('Stop and put my files back'),
            ),
          ),
        ],
        if (controller.onDisk case final LoadedSave onDisk) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            // After "prepare" the converted copy is staged but not in place yet.
            step == GuidedStep.prepared
                ? 'What the game will see after the next step'
                : 'What the game sees on disk now',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 8),
          SlotList(records: onDisk.records),
        ],
      ],
    );
  }
}

enum _StageState { waiting, current, done }

/// One numbered line of the guided checklist.
class _StageTile extends StatelessWidget {
  const _StageTile({
    required this.index,
    required this.text,
    required this.state,
    this.action,
  });

  final int index;
  final String text;
  final _StageState state;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Widget leading = switch (state) {
      _StageState.done => Icon(Icons.check_circle, color: scheme.primary),
      _StageState.current => Icon(Icons.arrow_circle_right, color: scheme.secondary),
      _StageState.waiting => Icon(Icons.circle_outlined, color: scheme.outline),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '$index. $text',
                  style: TextStyle(
                    color: state == _StageState.waiting ? scheme.onSurfaceVariant : scheme.onSurface,
                    fontWeight: state == _StageState.current ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
                if (action != null) ...<Widget>[const SizedBox(height: 8), action!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The one-button direct write, with its caveat.
class _DirectPanel extends StatelessWidget {
  const _DirectPanel({required this.controller});

  final InsertController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      const MessageBanner(
        tone: MessageTone.warning,
        message: 'Only sticks if iCloud leaves it alone',
        detail:
            'A save written from outside the game is not uploaded to iCloud, and the '
            'game may replace it with the cloud copy at launch. Use this when iCloud '
            'is off for FANTASIAN or the Mac is offline; otherwise use Guided.',
      ),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: controller.busy || !controller.hasSelection || controller.macFolder == null
              ? null
              : controller.writeDirect,
          icon: const Icon(Icons.save),
          label: const Text('Quit FANTASIAN, then write'),
        ),
      ),
      if (controller.macSave case final LoadedSave mac) ...<Widget>[
        const SizedBox(height: 12),
        Text('Currently on this Mac', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 8),
        SlotList(records: mac.records),
      ],
    ],
  );
}
