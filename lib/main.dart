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
import 'src/ui/home_shell.dart';
import 'src/ui/theme/fantasian_theme.dart';

void main() {
  runApp(const FantasianSgeApp());
}

/// The root widget.
class FantasianSgeApp extends StatelessWidget {
  /// Creates the app.
  const FantasianSgeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: AppInfo.name,
    debugShowCheckedModeBanner: false,
    theme: FantasianTheme.light(),
    darkTheme: FantasianTheme.dark(),
    home: const HomeShell(),
  );
}
