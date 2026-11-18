// Renders the live timing screen to PNG files for a visual check.
// Run with: flutter test --update-goldens test/screenshots
@Tags(['screenshot'])
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lap_timer/core/screen_awake_service.dart';
import 'package:lap_timer/features/race/domain/pit_stop.dart';
import 'package:lap_timer/features/race/domain/race_rules.dart';
import 'package:lap_timer/features/race/domain/stint.dart';
import 'package:lap_timer/features/timing/domain/lap.dart';
import 'package:lap_timer/features/timing/domain/lap_comparison.dart';
import 'package:lap_timer/features/timing/presentation/live_session_notifier.dart';
import 'package:lap_timer/features/timing/presentation/live_session_screen.dart';
import 'package:lap_timer/features/timing/presentation/live_session_state.dart';
import 'package:lap_timer/l10n/generated/app_localizations.dart';
import 'package:lap_timer/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';

class _NoopAwake implements ScreenAwakeService {
  @override
  Future<void> keepOn() async {}
  @override
  Future<void> release() async {}
}

class _FixedSession extends LiveSessionNotifier {
  _FixedSession(this.fixed);
  final LiveSessionState fixed;
  @override
  LiveSessionState build() => fixed;
  @override
  Future<void> start() async {}
}

Future<void> _loadFonts() async {
  const dir = '/opt/flutter/bin/cache/artifacts/material_fonts';
  final roboto = FontLoader('Roboto');
  for (final f in [
    'Roboto-Regular',
    'Roboto-Bold',
    'Roboto-Black',
    'Roboto-Medium',
  ]) {
    final bytes = File('$dir/$f.ttf').readAsBytesSync();
    roboto.addFont(Future.value(ByteData.view(bytes.buffer)));
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

const _laps = [
  Lap(
    number: 1,
    startMicros: 0,
    endMicros: 153750000,
    sectorMicros: [50680000, 65510000, 37560000],
  ),
  Lap(
    number: 2,
    startMicros: 153750000,
    endMicros: 303700000,
    sectorMicros: [48900000, 64270000, 36780000],
  ),
  Lap(
    number: 3,
    startMicros: 303700000,
    endMicros: 455180000,
    sectorMicros: [47870000, 66280000, 37330000],
  ),
];

Future<void> _shot(
  WidgetTester tester,
  LiveSessionState state,
  String name,
) async {
  tester.view.physicalSize = const Size(1688, 780);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        screenAwakeServiceProvider.overrideWithValue(_NoopAwake()),
        liveSessionProvider.overrideWith(() => _FixedSession(state)),
      ],
      child: MaterialApp(
        theme: AppTheme.dark().copyWith(
          textTheme: AppTheme.dark().textTheme.apply(fontFamily: 'Roboto'),
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const DefaultTextStyle(
          style: TextStyle(fontFamily: 'Roboto'),
          child: LiveSessionScreen(),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await expectLater(
    find.byType(LiveSessionScreen),
    matchesGoldenFile('out/$name.png'),
  );
  await tester.pumpWidget(const SizedBox());
}

void main() {
  setUpAll(_loadFonts);

  final now = DateTime.now().microsecondsSinceEpoch;
  testWidgets('three sectors, mid-lap', (tester) async {
    await _shot(
      tester,
      LiveSessionState(
        status: LiveSessionStatus.running,
        sectorCount: 3,
        compareMode: SectorCompareMode.bestLap,
        laps: _laps,
        lapNumber: 4,
        currentLapStartMicros: 455180000,
        currentSectorIndex: 2,
        currentLapSectors: const [48360000, 63790000],
        currentSectorStartMicros: 455180000 + 112150000,
        lastFixMicros: 455180000 + 112150000 + 35920000,
        lastFixWallMicros: now,
        speedKmh: 142,
        gpsRateHz: 10,
      ),
      'live_3_sectors',
    );
  });

  testWidgets('six sectors', (tester) async {
    await _shot(
      tester,
      LiveSessionState(
        status: LiveSessionStatus.running,
        sectorCount: 6,
        compareMode: SectorCompareMode.bestSector,
        laps: const [
          Lap(
            number: 1,
            startMicros: 0,
            endMicros: 133900000,
            sectorMicros: [
              20e6 ~/ 1,
              25e6 ~/ 1,
              25e6 ~/ 1,
              20e6 ~/ 1,
              22e6 ~/ 1,
              21900000,
            ],
          ),
        ],
        lapNumber: 2,
        currentLapStartMicros: 133900000,
        currentSectorIndex: 3,
        currentLapSectors: const [19880000, 25200000, 24690000],
        currentSectorStartMicros: 133900000 + 69770000,
        lastFixMicros: 133900000 + 69770000 + 8370000,
        lastFixWallMicros: now,
        gpsRateHz: 25,
      ),
      'live_6_sectors',
    );
  });

  const rules = RaceRules(id: 'r', name: 'Race');
  const entry = 1000000000;
  LiveSessionState pitState({
    required double speed,
    required int sinceEntrySeconds,
    PitView? pit,
    PitResult? result,
  }) => LiveSessionState(
    status: LiveSessionStatus.running,
    sectorCount: 3,
    compareMode: SectorCompareMode.bestLap,
    laps: _laps,
    lapNumber: 4,
    currentLapStartMicros: entry - 60000000,
    lastFixMicros: entry + sinceEntrySeconds * 1000000,
    lastFixWallMicros: now,
    speedKmh: speed,
    gpsRateHz: 10,
    raceRules: rules,
    pit: pit,
    pitResult: result,
    currentStint: const Stint(driverName: 'Nong', number: 1, startMicros: 0),
  );

  testWidgets('pit lane moving', (tester) async {
    await _shot(
      tester,
      pitState(
        speed: 52,
        sinceEntrySeconds: 43,
        pit: const PitView(
          entryMicros: entry,
          projectedExitPitMicros: 58900000,
          nextStintLabel: 'Nong(2)',
        ),
      ),
      'pit_moving',
    );
  });

  testWidgets('pit lane stopped', (tester) async {
    await _shot(
      tester,
      pitState(
        speed: 0,
        sinceEntrySeconds: 31,
        pit: const PitView(
          entryMicros: entry,
          showNextDriver: true,
          nextStintLabel: 'Nong(2)',
        ),
      ),
      'pit_stopped',
    );
  });

  testWidgets('pit exit result', (tester) async {
    await _shot(
      tester,
      pitState(
        speed: 70,
        sinceEntrySeconds: 62,
        result: PitResult(
          stop: const PitStop(
            number: 1,
            entryMicros: entry,
            exitMicros: entry + 61400000,
            maxSpeedKmh: 57,
            stopped: true,
          ),
          untilWallMicros: now + 10000000,
        ),
      ),
      'pit_result',
    );
  });
}
