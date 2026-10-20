/// The app's frame: a navigation rail on wide windows, a bottom bar on
/// phones, and the three tabs.
library;

import 'package:flutter/material.dart';

import '../core/save_locations.dart';
import '../core/save_transfer.dart';
import 'controllers/extract_controller.dart';
import 'controllers/insert_controller.dart';
import 'screens/about_screen.dart';
import 'screens/extract_screen.dart';
import 'screens/insert_screen.dart';
import 'widgets/decor.dart';

/// Hosts the Extract, Insert and About tabs.
class HomeShell extends StatefulWidget {
  /// Creates the shell. [locations] and [transfer] default to the real
  /// machine; tests pass stand-ins so they never touch a real save.
  const HomeShell({this.locations, this.transfer, super.key});

  /// Where to look for saves.
  final SaveLocations? locations;

  /// The transfer service (and with it, how the game process is detected).
  final SaveTransfer? transfer;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  /// Width above which the rail layout is used.
  static const double _wideLayoutBreakpoint = 720;

  int _index = 0;

  // The shell owns both controllers so a tab's state (a loaded save, a guided
  // insert in progress) lives exactly as long as the window does.
  late final ExtractController _extract = ExtractController(
    locations: widget.locations,
    transfer: widget.transfer,
  );
  late final InsertController _insert = InsertController(
    locations: widget.locations,
    transfer: widget.transfer,
  );

  @override
  void initState() {
    super.initState();
    _extract.discover();
    _insert.discover();
  }

  @override
  void dispose() {
    _extract.dispose();
    _insert.dispose();
    super.dispose();
  }

  static const List<(IconData, IconData, String)> _destinations = <(IconData, IconData, String)>[
    (Icons.upload_outlined, Icons.upload, 'Extract'),
    (Icons.download_outlined, Icons.download, 'Insert'),
    (Icons.info_outline, Icons.info, 'About'),
  ];

  @override
  Widget build(BuildContext context) {
    // IndexedStack keeps each tab's state (loaded saves, a guided insert in
    // progress) while the player switches tabs.
    final Widget pages = SkyBackground(
      child: IndexedStack(
        index: _index,
        children: <Widget>[
          ExtractScreen(controller: _extract),
          InsertScreen(controller: _insert),
          const AboutScreen(),
        ],
      ),
    );

    final bool wide = MediaQuery.sizeOf(context).width >= _wideLayoutBreakpoint;
    if (!wide) {
      return Scaffold(
        body: pages,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (int value) => setState(() => _index = value),
          destinations: <NavigationDestination>[
            for (final (IconData icon, IconData selected, String label) in _destinations)
              NavigationDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: label),
          ],
        ),
      );
    }
    return Scaffold(
      body: Row(
        children: <Widget>[
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (int value) => setState(() => _index = value),
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 20),
              child: Image.asset('assets/brand/logo.png', width: 56, height: 56),
            ),
            destinations: <NavigationRailDestination>[
              for (final (IconData icon, IconData selected, String label) in _destinations)
                NavigationRailDestination(
                  icon: Icon(icon),
                  selectedIcon: Icon(selected),
                  label: Text(label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: pages),
        ],
      ),
    );
  }
}
