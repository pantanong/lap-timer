// Renders the track tools (line editor, export/import) for a visual check
// (local only).
@Tags(['screenshot'])
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lap_timer/app/infrastructure_providers.dart';
import 'package:lap_timer/core/storage/json_file_store.dart';
import 'package:lap_timer/features/gps/gps_providers.dart';
import 'package:lap_timer/features/tracks/data/track_repository.dart';
import 'package:lap_timer/features/tracks/domain/gate_line.dart';
import 'package:lap_timer/features/tracks/domain/line_ref.dart';
import 'package:lap_timer/features/tracks/domain/track.dart';
import 'package:lap_timer/features/tracks/presentation/line_editor_screen.dart';
import 'package:lap_timer/features/tracks/presentation/track_editor_screen.dart';
import 'package:lap_timer/features/tracks/presentation/tracks_screen.dart';
import 'package:lap_timer/l10n/generated/app_localizations.dart';
import 'package:lap_timer/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';

Future<void> _loadFonts() async {
  const dir = '/opt/flutter/bin/cache/artifacts/material_fonts';
  final roboto = FontLoader('Roboto');
  for (final f in ['Roboto-Regular', 'Roboto-Bold', 'Roboto-Black']) {
    roboto.addFont(
      Future.value(ByteData.view(File('$dir/$f.ttf').readAsBytesSync().buffer)),
    );
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      Future.value(
        ByteData.view(
          File('$dir/MaterialIcons-Regular.otf').readAsBytesSync().buffer,
        ),
      ),
    );
  await icons.load();
}

const _track = Track(
  id: 't',
  name: 'Bira',
  startFinish: GateLine(
    latitude: 12.920540,
    longitude: 100.982310,
    travelBearingDegrees: 92,
  ),
  sectorLayouts: [
    SectorLayout(
      id: 'l3',
      name: 'Bira (3 Sectors)',
      splits: [
        GateLine(
          latitude: 12.9230,
          longitude: 100.9860,
          axisBearingDegrees: 20,
        ),
        GateLine(
          latitude: 12.9190,
          longitude: 100.9880,
          axisBearingDegrees: 70,
        ),
      ],
    ),
  ],
  defaultSectorLayoutId: 'l3',
);

Future<void> _shot(WidgetTester tester, Widget home, String file) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  tester.platformDispatcher.textScaleFactorTestValue = 1.3;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tracksProvider.overrideWith((ref) => Stream.value(const [_track])),
        gpsSourceProvider.overrideWithValue(null),
        trackRepositoryProvider.overrideWithValue(
          TrackRepository(JsonFileStore(Directory.systemTemp)),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.dark().copyWith(
          textTheme: AppTheme.dark().textTheme.apply(fontFamily: 'Roboto'),
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
  await expectLater(find.byWidget(home), matchesGoldenFile('out/$file'));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // flutter_map's tile cache asks for a cache folder.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => Directory.systemTemp.path,
        );
    await _loadFonts();
  });

  testWidgets('line editor: split', (t) async {
    await _shot(
      t,
      const LineEditorScreen(trackId: 't', lineRef: SplitLineRef('l3', 0)),
      'line_editor.png',
    );
  });

  testWidgets('line editor: scrolled', (t) async {
    const home = LineEditorScreen(
      trackId: 't',
      lineRef: SingleLineRef(TrackLine.startFinish),
    );
    await _shot(t, home, 'line_editor_sf.png');
    await t.tap(find.byTooltip('Move east (right)'));
    await t.tap(find.byIcon(Icons.rotate_right).first);
    await t.pump();
    await t.drag(find.byType(ListView), const Offset(0, -600));
    await t.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byWidget(home),
      matchesGoldenFile('out/line_editor_sf_scrolled.png'),
    );
  });

  testWidgets('track editor', (t) async {
    const home = TrackEditorScreen(trackId: 't');
    await _shot(t, home, 'track_editor.png');
    await t.drag(find.byType(ListView), const Offset(0, -700));
    await t.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byWidget(home),
      matchesGoldenFile('out/track_editor_scrolled.png'),
    );
  });

  testWidgets('tracks list', (t) async {
    await _shot(t, const TracksScreen(), 'tracks.png');
  });
}
