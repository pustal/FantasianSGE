/// FantasianSGE: moves FANTASIAN saves between the Apple Arcade release and
/// FANTASIAN Neo Dimension on Steam.
///
/// Layout of the code:
/// * `src/core`: save formats, file handling and the transfer procedures.
///   No Flutter imports, so it is unit-tested on its own.
/// * `src/ui`: theme, widgets, controllers (ChangeNotifier) and screens.
library;

import 'package:flutter/material.dart';

import 'src/core/constants.dart';
import 'src/core/save_locations.dart';
import 'src/core/save_transfer.dart';
import 'src/ui/home_shell.dart';
import 'src/ui/theme/fantasian_theme.dart';

void main() {
  runApp(const FantasianSgeApp());
}

/// The root widget.
class FantasianSgeApp extends StatelessWidget {
  /// Creates the app. The optional services replace the real ones in tests.
  const FantasianSgeApp({this.locations, this.transfer, super.key});

  /// Where to look for saves; the real machine when `null`.
  final SaveLocations? locations;

  /// The transfer service; the real one when `null`.
  final SaveTransfer? transfer;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: AppInfo.name,
    debugShowCheckedModeBanner: false,
    theme: FantasianTheme.light(),
    darkTheme: FantasianTheme.dark(),
    home: HomeShell(locations: locations, transfer: transfer),
  );
}
