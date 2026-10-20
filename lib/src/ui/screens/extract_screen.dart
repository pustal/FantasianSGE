/// The Extract tab: Apple Arcade save -> Neo Dimension `root.json`.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/constants.dart';
import '../../core/save_models.dart';
import '../controllers/extract_controller.dart';
import '../controllers/task_controller.dart';
import '../services/file_dialogs.dart';
import '../widgets/section_card.dart';
import '../widgets/slot_list.dart';
import 'page_frame.dart';

/// Lets the player read an Apple Arcade save and turn it into a Steam save.
class ExtractScreen extends StatefulWidget {
  /// Creates the screen.
  const ExtractScreen({this.dialogs = const FileDialogs(), this.controller, super.key});

  /// Native file dialogs (replaceable in tests).
  final FileDialogs dialogs;

  /// An externally owned controller (for tests and previews). When `null`
  /// the screen creates and disposes its own.
  final ExtractController? controller;

  @override
  State<ExtractScreen> createState() => _ExtractScreenState();
}

class _ExtractScreenState extends State<ExtractScreen> {
  late final ExtractController _controller = widget.controller ?? ExtractController();

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
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  FileDialogs get _dialogs => widget.dialogs;

  Future<void> _pickSourceFiles() async {
    final List<String> paths = await _dialogs.pickFiles(
      title: 'Pick a FANTASIAN zip, SaveDataEntity.sqlite (+ -wal, -shm) or root.json',
    );
    if (paths.isNotEmpty) {
      await _controller.loadFiles(paths);
    }
  }

  Future<void> _pickSourceFolder() async {
    final String? folder = await _dialogs.pickFolder(title: 'Pick the FANTASIAN save folder');
    if (folder != null) {
      await _controller.loadFolder(folder);
    }
  }

  Future<void> _pickTemplate() async {
    final List<String> paths = await _dialogs.pickFiles(title: 'Pick your Neo Dimension root.json');
    if (paths.isNotEmpty) {
      await _controller.loadTemplate(paths.first);
    }
  }

  Future<void> _saveAs() async {
    final Uint8List bytes;
    try {
      bytes = _controller.buildRootJson();
    } on Object catch (error) {
      _controller.showError(error);
      return;
    }
    final String? path = await _dialogs.saveBytes(
      title: 'Save the Neo Dimension save',
      fileName: SteamConstants.rootFileName,
      bytes: bytes,
      mimeType: 'application/json',
    );
    if (path != null) {
      _controller.reportSaved(path);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (BuildContext context, Widget? _) => PageFrame(
      title: 'Apple Arcade to Steam',
      intro:
          'Turn your Apple Arcade save (Mac, iPhone or iPad) into a root.json for '
          'FANTASIAN Neo Dimension on Steam.',
      children: <Widget>[
        _sourceStep(context),
        _mergeStep(context),
        _outputStep(context),
        if (_controller.busy) const LinearProgressIndicator(),
        if (_controller.error case final Object error) MessageBanner.fromError(error),
        if (_controller.result case final ResultMessage result)
          MessageBanner(tone: result.tone, message: result.message, detail: result.detail),
      ],
    ),
  );

  Widget _sourceStep(BuildContext context) {
    final LoadedSave? source = _controller.source;
    final bool busy = _controller.busy;
    return SectionCard(
      step: 1,
      title: 'Find your Apple Arcade save',
      description: _controller.macFolder != null
          ? 'FANTASIAN has saved on this Mac. Use it, or pick a save copied from elsewhere.'
          : 'Pick the FANTASIAN save folder (or a zip of it) copied from a Mac. '
                'It lives at ${_controller.macFolderHint}. Copy the whole folder: '
                'your latest progress is in SaveDataEntity.sqlite-wal.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ButtonRow(
            children: <Widget>[
              if (_controller.macFolder != null)
                FilledButton.icon(
                  onPressed: busy ? null : _controller.loadMacSave,
                  icon: const Icon(Icons.laptop_mac),
                  label: const Text('Use this Mac\'s save'),
                ),
              if (_dialogs.canPickFolders)
                OutlinedButton.icon(
                  onPressed: busy ? null : _pickSourceFolder,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Choose folder…'),
                ),
              OutlinedButton.icon(
                onPressed: busy ? null : _pickSourceFiles,
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('Choose files or zip…'),
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
              onToggle: _controller.toggle,
            ),
          ],
        ],
      ),
    );
  }

  Widget _mergeStep(BuildContext context) {
    final LoadedSave? template = _controller.template;
    final bool busy = _controller.busy;
    return SectionCard(
      step: 2,
      enabled: _controller.source != null,
      title: 'Keep your Steam progress? (optional)',
      description:
          'Merge into your existing Neo Dimension root.json: matching slots are '
          'replaced, every other Steam slot stays as it is. Without this, a fresh '
          'file holding only the Apple Arcade slots is written.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Merge into an existing Neo Dimension save'),
            value: _controller.merge,
            onChanged: busy ? null : _controller.setMerge,
          ),
          if (_controller.merge) ...<Widget>[
            if (_controller.steamRoots.length > 1)
              DropdownButtonFormField<String>(
                initialValue: _controller.templatePath,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Neo Dimension save on this computer'),
                items: <DropdownMenuItem<String>>[
                  for (final String root in _controller.steamRoots)
                    DropdownMenuItem<String>(value: root, child: Text(root, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (String? value) => value == null ? null : _controller.loadTemplate(value),
              ),
            const SizedBox(height: 8),
            ButtonRow(
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: busy ? null : _pickTemplate,
                  icon: const Icon(Icons.file_open_outlined),
                  label: const Text('Choose root.json…'),
                ),
              ],
            ),
            if (template != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                'Merging into ${_controller.templatePath ?? template.sourceDescription}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 8),
              SlotList(
                records: template.records,
                highlight: _controller.willReplace,
                highlightLabel: 'replaced',
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _outputStep(BuildContext context) {
    final bool ready = _controller.readyToExport && !_controller.busy;
    return SectionCard(
      step: 3,
      enabled: _controller.source != null,
      title: 'Create the Steam save',
      description:
          'Records are encrypted the way Neo Dimension expects and checked by '
          'reading them back before anything is written. Close the game before '
          'replacing its save.',
      child: ButtonRow(
        children: <Widget>[
          FilledButton.icon(
            onPressed: ready ? _saveAs : null,
            icon: const Icon(Icons.save_alt),
            label: const Text('Save root.json…'),
          ),
          if (_controller.canInstall)
            OutlinedButton.icon(
              onPressed: ready ? _controller.installIntoGame : null,
              icon: const Icon(Icons.download_done),
              label: const Text('Install into Neo Dimension'),
            ),
        ],
      ),
    );
  }
}
