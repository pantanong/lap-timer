// Renders the bottom of the New Session screen with an Android navigation
// bar inset, for a visual check (local only).
@Tags(['screenshot'])
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lap_timer/app/infrastructure_providers.dart';
import 'package:lap_timer/features/race/data/race_rules_repository.dart';
import 'package:lap_timer/features/sessions/presentation/new_session_screen.dart';
import 'package:lap_timer/features/tracks/data/simulator_track_preset.dart';
import 'package:lap_timer/l10n/generated/app_localizations.dart';
import 'package:lap_timer/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';

Future<void> _loadFonts() async {
  const dir = '/opt/flutter/bin/cache/artifacts/material_fonts';
  final roboto = FontLoader('Roboto');
  for (final f in ['Roboto-Regular', 'Roboto-Bold', 'Roboto-Medium']) {
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

  testWidgets('new session, scrolled to the bottom', (tester) async {
    // A phone like the user's: 390 x 844 dp with a 48 dp navigation bar.
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    tester.view.padding = const FakeViewPadding(bottom: 96, top: 48);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tracksProvider.overrideWith(
            (ref) => Stream.value([simulatorTrackPreset()]),
          ),
          raceRulesProvider.overrideWith(
            (ref) => Stream.value([RaceRulesRepository.defaultRules]),
          ),
          brakeProfilesProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: MaterialApp(
          theme: AppTheme.dark().copyWith(
            textTheme: AppTheme.dark().textTheme.apply(fontFamily: 'Roboto'),
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const NewSessionScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(NewSessionScreen),
      matchesGoldenFile('out/new_session_bottom.png'),
    );
  });
}
