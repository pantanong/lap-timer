// Renders the Corners screen for a visual check (local only).
@Tags(['screenshot'])
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lap_timer/app/infrastructure_providers.dart';
import 'package:lap_timer/features/brake_coach/domain/brake_profile.dart';
import 'package:lap_timer/features/brake_coach/presentation/corners_screen.dart';
import 'package:lap_timer/features/sessions/domain/session.dart';
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

void main() {
  setUpAll(_loadFonts);

  testWidgets('corners screen', (tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final session = Session(
      id: 's1',
      trackId: 'missing-track',
      trackName: 'Bira',
      sectorLayoutName: '3 sectors',
      sectorCount: 3,
      vehicleType: VehicleType.car,
      startedAt: DateTime(2026, 11, 25),
      laps: const [],
      brakeProfile: const BrakeProfile(
        id: 'p',
        name: 'Bira – car – 2026-11-25',
        trackId: 'missing-track',
        vehicleType: VehicleType.car,
        pathLatLng: [],
        corners: [
          CornerBrakePoint(
            brakeDistanceMetres: 412,
            latitude: 0,
            longitude: 0,
            sourceLapNumber: 2,
          ),
          CornerBrakePoint(
            brakeDistanceMetres: 1284,
            latitude: 0,
            longitude: 0,
            offsetMetres: -5,
            locked: true,
            sourceLapNumber: 5,
          ),
        ],
      ),
      brakeMisses: const {
        0: [12, 11, 2, 14, 13],
      },
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionsProvider.overrideWith((ref) => Stream.value([session])),
          tracksProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: MaterialApp(
          theme: AppTheme.dark().copyWith(
            textTheme: AppTheme.dark().textTheme.apply(fontFamily: 'Roboto'),
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const CornersScreen(sessionId: 's1'),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await expectLater(
      find.byType(CornersScreen),
      matchesGoldenFile('out/corners.png'),
    );
  });
}
