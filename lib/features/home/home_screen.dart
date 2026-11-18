import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lap_timer/app/routes.dart';
import 'package:lap_timer/features/gps/data/gps_log_repository.dart';
import 'package:lap_timer/features/gps/gps_providers.dart';
import 'package:lap_timer/l10n/generated/app_localizations.dart';
import 'package:lap_timer/theme/app_colors.dart';
import 'package:material_ui/material_ui.dart';

/// Start screen: choose the GPS source and open the tools.
class HomeScreen extends ConsumerWidget {
  /// Creates the screen.
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final choice = ref.watch(gpsSourceChoiceProvider);
    final source = ref.watch(gpsSourceProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.appTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionTitle(l10n.homeGpsSourceTitle),
          const _SourcePicker(),
          if (choice is ReplayGpsChoice) ...[
            const SizedBox(height: 16),
            _SectionTitle(l10n.homeRecordedLogsTitle),
            const _LogList(),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: source == null
                ? null
                : () => context.push(AppRoutes.gpsMonitor),
            child: Text(
              source == null
                  ? l10n.homeSelectLogFirst
                  : l10n.homeOpenGpsMonitor,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        color: AppColors.of(context).textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ),
    ),
  );
}

enum _SourceKind { phone, simulator, replay }

class _SourcePicker extends ConsumerWidget {
  const _SourcePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final choice = ref.watch(gpsSourceChoiceProvider);
    final selected = switch (choice) {
      PhoneGpsChoice() => _SourceKind.phone,
      SimulatorGpsChoice() => _SourceKind.simulator,
      ReplayGpsChoice() => _SourceKind.replay,
    };
    return SegmentedButton<_SourceKind>(
      segments: [
        ButtonSegment(
          value: _SourceKind.phone,
          label: Text(l10n.gpsSourcePhone),
        ),
        ButtonSegment(
          value: _SourceKind.simulator,
          label: Text(l10n.gpsSourceSimulator),
        ),
        ButtonSegment(
          value: _SourceKind.replay,
          label: Text(l10n.gpsSourceReplay),
        ),
      ],
      selected: {selected},
      onSelectionChanged: (kinds) {
        ref
            .read(gpsSourceChoiceProvider.notifier)
            .choice = switch (kinds.single) {
          _SourceKind.phone => const PhoneGpsChoice(),
          _SourceKind.simulator => const SimulatorGpsChoice(),
          _SourceKind.replay => const ReplayGpsChoice(),
        };
      },
    );
  }
}

class _LogList extends ConsumerWidget {
  const _LogList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final logs = ref.watch(gpsLogsProvider);
    final choice = ref.watch(gpsSourceChoiceProvider);
    final selectedPath = choice is ReplayGpsChoice ? choice.log?.path : null;
    return switch (logs) {
      AsyncData(:final value) when value.isEmpty => Text(l10n.homeNoLogs),
      AsyncData(:final value) => Column(
        children: [
          for (final log in value)
            _LogTile(log: log, selected: log.path == selectedPath),
        ],
      ),
      AsyncError() => Text(l10n.errorGpsLogUnavailable),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _LogTile extends ConsumerWidget {
  const _LogTile({required this.log, required this.selected});

  final GpsLogInfo log;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
    child: ListTile(
      title: Text(log.fileName),
      trailing: selected ? const Icon(Icons.check) : null,
      onTap: () => ref.read(gpsSourceChoiceProvider.notifier).choice =
          ReplayGpsChoice(log),
    ),
  );
}
