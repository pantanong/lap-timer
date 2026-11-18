import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lap_timer/app/infrastructure_providers.dart';
import 'package:lap_timer/app/routes.dart';
import 'package:lap_timer/features/timing/domain/lap_comparison.dart';
import 'package:lap_timer/features/timing/presentation/time_format.dart';
import 'package:lap_timer/l10n/generated/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

/// History: every recorded session, newest first.
class SessionsScreen extends ConsumerWidget {
  /// Creates the screen.
  const SessionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final sessions = ref.watch(sessionsProvider);
    final dateFormat = DateFormat.yMMMd().add_Hm();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.historyTitle)),
      body: switch (sessions) {
        AsyncData(:final value) when value.isEmpty => Center(
          child: Text(l10n.historyEmpty),
        ),
        AsyncData(:final value) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final s in value)
              Card(
                child: ListTile(
                  title: Text(s.trackName),
                  subtitle: Text(
                    '${dateFormat.format(s.startedAt.toLocal())} · '
                    '${l10n.historyLaps(s.laps.length)}',
                  ),
                  trailing: Text(switch (LapReferences.from(
                    s.racingLaps,
                    sectorCount: s.sectorCount,
                  ).bestLap) {
                    final best? => formatLapTime(best.timeMicros),
                    null => '—',
                  }),
                  onTap: () => context.push(AppRoutes.sessionDetail(s.id)),
                ),
              ),
          ],
        ),
        AsyncError() => Center(child: Text(l10n.errorGeneric)),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}
