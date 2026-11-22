import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lap_timer/app/infrastructure_providers.dart';
import 'package:lap_timer/app/routes.dart';
import 'package:lap_timer/core/ui/page_padding.dart';
import 'package:lap_timer/features/sessions/domain/session.dart';
import 'package:lap_timer/features/timing/domain/lap_comparison.dart';
import 'package:lap_timer/features/timing/presentation/time_format.dart';
import 'package:lap_timer/l10n/generated/app_localizations.dart';
import 'package:lap_timer/theme/app_colors.dart';
import 'package:lap_timer/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';

/// Summary of one session: best lap, optimal lap and the laps table with
/// the best value of each column highlighted (purple).
class SessionDetailScreen extends ConsumerWidget {
  /// Shows the session with [sessionId].
  const SessionDetailScreen({required this.sessionId, super.key});

  /// Session shown.
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final sessions = ref.watch(sessionsProvider).value ?? const <Session>[];
    final matches = sessions.where((s) => s.id == sessionId);
    if (matches.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(l10n.errorGeneric)),
      );
    }
    final session = matches.first;
    // Laps through the pit lane never count as best lap / best sector.
    final refs = LapReferences.from(
      session.racingLaps,
      sectorCount: session.sectorCount,
    );
    final best = refs.bestLap;
    final optimal = refs.optimalLapMicros;
    return Scaffold(
      appBar: AppBar(title: Text(session.trackName)),
      body: ListView(
        padding: pagePadding(context),
        children: [
          Text(session.sectorLayoutName),
          const SizedBox(height: 12),
          Row(
            children: [
              _Stat(
                l10n.liveBest,
                best == null ? '—' : formatLapTime(best.timeMicros),
              ),
              _Stat(
                l10n.sessionOptimal,
                optimal == null ? '—' : formatLapTime(optimal),
              ),
              _Stat(l10n.sessionLapCount, '${session.laps.length}'),
            ],
          ),
          if (session.pitStops.isNotEmpty) _PitStopsCard(session: session),
          if (session.brakeProfile != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: FilledButton.tonalIcon(
                onPressed: () => context.push(AppRoutes.corners(session.id)),
                icon: const Icon(Icons.speed),
                label: Text(l10n.sessionBrakePoints),
              ),
            ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _LapsTable(session: session, refs: refs),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(
                color: AppColors.of(context).textMuted,
                fontSize: 11,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                fontFeatures: AppTheme.tabularFigures,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _LapsTable extends StatelessWidget {
  const _LapsTable({required this.session, required this.refs});

  final Session session;
  final LapReferences refs;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    const mono = TextStyle(fontFeatures: AppTheme.tabularFigures);
    final best = TextStyle(
      color: colors.personalBest,
      fontFeatures: AppTheme.tabularFigures,
    );
    return DataTable(
      columnSpacing: 20,
      columns: [
        DataColumn(label: Text(l10n.sessionLapColumn)),
        if (session.stints.isNotEmpty)
          DataColumn(label: Text(l10n.sessionDriverColumn)),
        for (var i = 0; i < session.sectorCount; i++)
          DataColumn(label: Text('S${i + 1}')),
        DataColumn(label: Text(l10n.sessionTimeColumn)),
      ],
      rows: [
        for (final lap in session.laps)
          DataRow(
            cells: [
              DataCell(
                Text(
                  session.isPitLap(lap)
                      ? '${lap.number} ${l10n.sessionPitMark}'
                      : '${lap.number}',
                ),
              ),
              if (session.stints.isNotEmpty)
                DataCell(Text(session.stintOf(lap)?.label ?? '')),
              for (var i = 0; i < session.sectorCount; i++)
                DataCell(
                  Text(
                    switch (i < lap.sectorMicros.length
                        ? lap.sectorMicros[i]
                        : null) {
                      final int t => formatLapTime(t),
                      null => '—',
                    },
                    style:
                        i < lap.sectorMicros.length &&
                            lap.sectorMicros[i] != null &&
                            lap.sectorMicros[i] == refs.bestSectorMicros[i]
                        ? best
                        : mono,
                  ),
                ),
              DataCell(
                Text(
                  formatLapTime(lap.timeMicros),
                  style: lap == refs.bestLap ? best : mono,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _PitStopsCard extends StatelessWidget {
  const _PitStopsCard({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.sessionPitStops,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            for (final stop in session.pitStops)
              Text(
                l10n.sessionPitStopLine(
                  stop.number,
                  formatLapTime(stop.durationMicros),
                  stop.maxSpeedKmh.round(),
                ),
                style: const TextStyle(fontFeatures: AppTheme.tabularFigures),
              ),
          ],
        ),
      ),
    );
  }
}
