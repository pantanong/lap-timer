// Renders the live timing screen to PNG files for a visual check.
// Run with: flutter test --update-goldens test/screenshots
@Tags(['screenshot'])
library;

import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lap_timer/app/infrastructure_providers.dart';
import 'package:lap_timer/core/screen_awake_service.dart';
import 'package:lap_timer/features/brake_coach/domain/brake_alert.dart';
import 'package:lap_timer/features/brake_coach/domain/brake_coach.dart';
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
        // Freeze wall time so timed displays render deterministically.
        clockProvider.overrideWithValue(Clock.fixed(_frozenNow)),
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

/// Wall time all screenshots are rendered at.
final DateTime _frozenNow = DateTime.now();

void main() {
  setUpAll(_loadFonts);

  final now = _frozenNow.microsecondsSinceEpoch;
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

  LiveSessionState alertState(BrakeAlert alert) => LiveSessionState(
    status: LiveSessionStatus.running,
    sectorCount: 3,
    compareMode: SectorCompareMode.bestLap,
    laps: _laps,
    lapNumber: 5,
    currentLapStartMicros: 455180000,
    lastFixMicros: 455180000 + 30000000,
    lastFixWallMicros: now,
    speedKmh: 168,
    gpsRateHz: 10,
    brakeAlert: alert,
    brakeCoachPhase: BrakeCoachPhase.active,
  );

  testWidgets('brake alert yellow', (tester) async {
    await _shot(
      tester,
      alertState(
        const BrakeAlert(
          phase: BrakeAlertPhase.approaching,
          cornerIndex: 2,
          metresToBrakePoint: 72,
        ),
      ),
      'brake_yellow',
    );
  });

  testWidgets('brake alert red', (tester) async {
    await _shot(
      tester,
      alertState(
        const BrakeAlert(phase: BrakeAlertPhase.brakeNow, cornerIndex: 2),
      ),
      'brake_red',
    );
  });

  // Gap display: the user's real numbers from the Dragy test.
  LiveSessionState gapState({
    SectorFlash? sector,
    LapFlash? lapFlash,
    List<int?> sectors = const [14880000, 10150000],
    int sectorIndex = 2,
    int? liveDelta = -1320000,
  }) => LiveSessionState(
    status: LiveSessionStatus.running,
    sectorCount: 3,
    compareMode: SectorCompareMode.bestLap,
    laps: const [
      Lap(
        number: 2,
        startMicros: 0,
        endMicros: 127300000,
        sectorMicros: [17140000, 12900000, 97260000],
      ),
      Lap(
        number: 3,
        startMicros: 127300000,
        endMicros: 258120000,
        sectorMicros: [17500000, 13000000, 100320000],
      ),
    ],
    lapNumber: 4,
    currentLapStartMicros: 258120000,
    currentSectorIndex: sectorIndex,
    currentLapSectors: sectors,
    currentSectorStartMicros: 258120000 + 25030000,
    lastFixMicros: 258120000 + 104400000,
    lastFixWallMicros: now,
    gpsRateHz: 10,
    sectorFlash: sector,
    flash: lapFlash,
    liveDeltaMicros: liveDelta,
  );

  testWidgets('gap 1: running (larger predicted / last / best)', (t) async {
    await _shot(t, gapState(), 'gap_1_running');
  });

  testWidgets('gap 2: just finished sector 2', (t) async {
    await _shot(
      t,
      gapState(
        sector: SectorFlash(
          sectorIndex: 1,
          sectorMicros: 10150000,
          deltaMicros: -2750000,
          untilWallMicros: now + 5000000,
        ),
      ),
      'gap_2_sector',
    );
  });

  const finished = Lap(
    number: 4,
    startMicros: 258120000,
    endMicros: 380700000,
    sectorMicros: [14880000, 10150000, 97550000],
  );
  testWidgets('gap 3: lap end, last sector first', (t) async {
    await _shot(
      t,
      gapState(
        sectors: const [],
        sectorIndex: 0,
        lapFlash: LapFlash(
          lap: finished,
          deltaMicros: -4720000,
          isBest: true,
          startedWallMicros: now,
          lastSector: SectorFlash(
            sectorIndex: 2,
            sectorMicros: 97550000,
            deltaMicros: 290000,
            untilWallMicros: now + 2000000,
          ),
          lastSectorHoldMicros: 2000000,
          untilWallMicros: now + 7000000,
        ),
      ),
      'gap_3_last_sector',
    );
  });

  testWidgets('gap 4: lap end, then the lap gap', (t) async {
    await _shot(
      t,
      gapState(
        sectors: const [],
        sectorIndex: 0,
        lapFlash: LapFlash(
          lap: finished,
          deltaMicros: -4720000,
          isBest: true,
          startedWallMicros: now - 3000000,
          lastSector: SectorFlash(
            sectorIndex: 2,
            sectorMicros: 97550000,
            deltaMicros: 290000,
            untilWallMicros: now - 1000000,
          ),
          lastSectorHoldMicros: 2000000,
          untilWallMicros: now + 4000000,
        ),
      ),
      'gap_4_lap',
    );
  });

  testWidgets('user phone: lap 1, 4 sectors, system font 130 %', (t) async {
    t.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await _shot(
      t,
      LiveSessionState(
        status: LiveSessionStatus.running,
        sectorCount: 4,
        compareMode: SectorCompareMode.bestLap,
        currentLapStartMicros: 1000000,
        currentSectorStartMicros: 1000000,
        lastFixMicros: 17300000,
        lastFixWallMicros: now,
        gpsRateHz: 10,
        raceRules: const RaceRules(id: 'r', name: 'Race'),
      ),
      'user_lap1_4sectors',
    );
  });
}
