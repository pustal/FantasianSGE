/// Widget tests for the screens, driven with real fixture saves.
///
/// Screenshots for the README are only taken on request, because golden
/// images differ slightly between machines and would make CI flaky:
///
/// ```sh
/// SCREENSHOTS=1 flutter test test/ui --update-goldens
/// ```
///
/// writes them to `docs/screenshots/`.
library;

import 'dart:io';

import 'package:fantasian_sge/main.dart';
import 'package:fantasian_sge/src/core/save_loader.dart';
import 'package:fantasian_sge/src/core/save_locations.dart';
import 'package:fantasian_sge/src/core/save_models.dart';
import 'package:fantasian_sge/src/core/save_transfer.dart';
import 'package:fantasian_sge/src/ui/controllers/extract_controller.dart';
import 'package:fantasian_sge/src/ui/controllers/insert_controller.dart';
import 'package:fantasian_sge/src/ui/screens/extract_screen.dart';
import 'package:fantasian_sge/src/ui/screens/insert_screen.dart';
import 'package:fantasian_sge/src/ui/theme/fantasian_theme.dart';
import 'package:fantasian_sge/src/ui/widgets/decor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/fixtures.dart';

/// Loads the bundled fonts so screenshots show real text, not test boxes.
Future<void> loadFonts() async {
  for (final (String family, List<String> files) in <(String, List<String>)>[
    ('Cinzel', <String>['assets/fonts/Cinzel.ttf']),
    ('Nunito', <String>['assets/fonts/Nunito.ttf']),
    ('MaterialIcons', <String>[_materialIconsPath()]),
  ]) {
    final FontLoader loader = FontLoader(family);
    for (final String file in files) {
      final Uint8List bytes = File(file).readAsBytesSync();
      loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
}

/// The Material icon font shipped with the Flutter SDK.
String _materialIconsPath() {
  final String flutterRoot = Platform.environment['FLUTTER_ROOT'] ??
      p.dirname(p.dirname(p.dirname(Platform.resolvedExecutable)));
  return p.join(flutterRoot, 'bin', 'cache', 'artifacts', 'material_fonts', 'MaterialIcons-Regular.otf');
}

/// Wraps [child] the way the app shell does.
Widget frame(Widget child, {Brightness brightness = Brightness.dark}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: brightness == Brightness.dark ? FantasianTheme.dark() : FantasianTheme.light(),
  home: Scaffold(body: SkyBackground(child: child)),
);

/// Saves a screenshot of the app to `docs/screenshots/[name]` when the
/// `SCREENSHOTS` environment variable is set.
Future<void> screenshot(String name) async {
  if (Platform.environment['SCREENSHOTS'] == null) {
    return;
  }
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('../../docs/screenshots/$name'));
}

void main() {
  setUpAll(loadFonts);

  late Directory home;
  setUp(() async {
    home = await Directory.systemTemp.createTemp('fsge_home_');
  });
  tearDown(() async => home.delete(recursive: true));

  /// Locations that behave like a Mac whose FANTASIAN save is [home]'s.
  SaveLocations macLocations() =>
      SaveLocations(platform: 'macos', environment: <String, String>{'HOME': home.path});

  Directory macSaveFolder() => Directory(p.joinAll(<String>[
    home.path,
    'Library', 'Containers', 'com.mistwalkercorp.fantasian', 'Data', 'Library',
    'Application Support', 'FANTASIAN',
  ]));

  testWidgets('the app starts on the Extract tab', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const FantasianSgeApp());
    await tester.pumpAndSettle();
    expect(find.text('Apple Arcade to Steam'), findsOneWidget);
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();
    expect(find.text('Source on GitHub'), findsOneWidget);
    expect(find.text('Buy me a Ko-fi'), findsOneWidget);
  });

  testWidgets('phone layout uses a bottom bar and fits the About tab', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1500);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(const FantasianSgeApp());
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull); // no overflow errors

    // Images decode asynchronously; let them finish before the screenshot.
    await tester.runAsync(() async {
      for (final Element element in find.byType(Image).evaluate()) {
        if (element.widget case final Image image) {
          await precacheImage(image.image, element);
        }
      }
    });
    await tester.pumpAndSettle();
    await screenshot('about_phone_dark.png');
  });

  testWidgets('extract: loads this Mac\'s save and lists its slots', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final ExtractController controller = ExtractController(locations: macLocations());
    await tester.runAsync(() async {
      await writeArcadeDatabase(macSaveFolder());
      await controller.discover();
      await controller.loadMacSave();
    });
    await tester.pumpWidget(frame(ExtractScreen(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text('Autosave'), findsOneWidget);
    expect(find.text('Slot 10'), findsOneWidget);
    expect(find.textContaining('35,868 G'), findsOneWidget);
    await screenshot('extract_dark.png');
  });

  testWidgets('insert: guided procedure walks through every step', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final InsertController controller = InsertController(locations: macLocations());
    await tester.runAsync(() async {
      await writeArcadeDatabase(macSaveFolder());
      // A Steam save holding two slots, one of which replaces a Mac slot.
      final String root = p.join(home.path, 'root.json');
      final LoadedSave macSave = await SaveLoader().loadFolder(macSaveFolder().path);
      final String json = SaveTransfer()
          .buildSteamRoot(macSave, <String>{'Data/GameData2.json', 'Data/GameData10.json'})
          .json;
      await File(root).writeAsString(json);
      await controller.discover();
      await controller.loadSteam(root);
    });
    await tester.pumpWidget(frame(InsertScreen(controller: controller), brightness: Brightness.light));
    await tester.pumpAndSettle();
    expect(find.text('replaces Mac slot'), findsNWidgets(2));

    await tester.runAsync(controller.startGuided);
    await tester.pumpAndSettle();
    expect(find.text('Game is on the main menu'), findsOneWidget);
    await screenshot('insert_guided_light.png');

    await tester.runAsync(controller.advanceGuided); // swap in
    await tester.runAsync(controller.advanceGuided); // swap back
    await tester.runAsync(controller.advanceGuided); // finish
    await tester.pumpAndSettle();
    expect(controller.error, isNull);
    expect(find.textContaining('The save now belongs to this Mac'), findsOneWidget);
    // This Mac's own files are back in place after the procedure.
    expect(controller.macSave?.records, hasLength(4));
  });
}
