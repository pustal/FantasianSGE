/// The About tab: what the app does, how saves work, links and credits.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../widgets/decor.dart';
import 'page_frame.dart';

/// Project information, help, the GitHub and Ko-fi links, and credits.
class AboutScreen extends StatelessWidget {
  /// Creates the screen.
  const AboutScreen({super.key});

  /// Opens [uri] in the browser, telling the player if that fails.
  Future<void> _open(BuildContext context, Uri uri) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      messenger.showSnackBar(SnackBar(content: Text('Could not open $uri')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return PageFrame(
      title: 'About',
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: <Widget>[
                const BrandHeader(),
                const SizedBox(height: 4),
                Text(
                  'Version ${AppInfo.version} · Build ${AppInfo.buildStamp}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                Text(
                  'Moves your FANTASIAN progress between the Apple Arcade release '
                  '(Mac, iPhone, iPad) and FANTASIAN Neo Dimension on Steam, in '
                  'both directions.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 20),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: () => _open(context, AppLinks.github),
                      icon: const Icon(Icons.code),
                      label: const Text('Source on GitHub'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _open(context, AppLinks.kofi),
                      icon: const Icon(Icons.local_cafe_outlined),
                      label: const Text('Buy me a Ko-fi'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const _HelpCard(),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Thanks', style: theme.textTheme.titleLarge),
                const SizedBox(height: 10),
                const Text(
                  'uior, Xsonicdragon and Square_Ad1583 on Reddit, for their saves '
                  'and debugging help with the original script.',
                ),
                const SizedBox(height: 8),
                const Text(
                  'mathcodergamer (FantasianND-Save-Editor), who worked out the Neo '
                  'Dimension format and its encryption, and RobThePCGuy '
                  '(Fantasian-Save-Transfer), whose research into iCloud and the '
                  'game\'s slot layout the Insert tab follows.',
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  children: <Widget>[
                    TextButton(
                      onPressed: () => _open(context, AppLinks.ndSaveEditor),
                      child: const Text('FantasianND-Save-Editor'),
                    ),
                    TextButton(
                      onPressed: () => _open(context, AppLinks.saveTransfer),
                      child: const Text('Fantasian-Save-Transfer'),
                    ),
                  ],
                ),
                const OrnamentDivider(),
                Text(
                  'GPL-3.0. Not affiliated with Mistwalker, Square Enix or Apple. '
                  'Always keep a backup, and check a moved save in game before '
                  'putting more hours on top of it.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// How saves work on each platform, as expandable answers.
class _HelpCard extends StatelessWidget {
  const _HelpCard();

  static const List<(String, String)> _entries = <(String, String)>[
    (
      'Where is my Apple Arcade save?',
      'On a Mac: ~/Library/Containers/com.mistwalkercorp.fantasian/Data/Library/'
          'Application Support/FANTASIAN. It is a Core Data database '
          '(SaveDataEntity.sqlite) and the latest progress usually sits in its -wal '
          'file, so always copy the whole folder.',
    ),
    (
      'I play on iPhone or iPad',
      'iOS keeps every app\'s files private, so no app can read FANTASIAN\'s save '
          'directly. The game syncs through iCloud, though: install FANTASIAN on a '
          'Mac signed in to the same Apple Account, launch it once so the save '
          'downloads, and run this app there. Inserting works the same way in '
          'reverse. On iOS this app still converts files you bring to it (a '
          'FANTASIAN zip or a root.json) through the Files app.',
    ),
    (
      'Where is my Steam save?',
      r'Windows: Documents\My Games\FANTASIAN Neo Dimension\Steam\<steam id>\_data\root.json. '
          'Steam Deck / Linux: the same path inside '
          'steamapps/compatdata/2844850/pfx/drive_c/users/steamuser/. '
          'If the game never saved, start a new game and save once first.',
    ),
    (
      'Which slot is which?',
      'GameData0 is the autosave and GameData1 to GameData10 are Slots 1 to 10, '
          'as shown on the game\'s Load screen.',
    ),
    (
      'What changed from the old script?',
      'FantasianSGE 0.1 wrote the save unencrypted. Neo Dimension now reads '
          'encrypted records, which this app writes. Files made by the old script '
          'can still be opened here and converted properly.',
    ),
  ];

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: 8),
          Text('How saves work', style: Theme.of(context).textTheme.titleLarge),
          for (final (String question, String answer) in _entries)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(question),
              expandedAlignment: Alignment.centerLeft,
              childrenPadding: const EdgeInsets.only(bottom: 12),
              children: <Widget>[SelectableText(answer)],
            ),
        ],
      ),
    ),
  );
}
