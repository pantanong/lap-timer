import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lap_timer/app/infrastructure_providers.dart';
import 'package:lap_timer/app/routes.dart';
import 'package:lap_timer/features/gps/gps_providers.dart';
import 'package:lap_timer/features/race/domain/race_rules.dart';
import 'package:lap_timer/features/race/presentation/race_rules_screen.dart';
import 'package:lap_timer/features/sessions/domain/session.dart';
import 'package:lap_timer/features/timing/domain/lap_comparison.dart';
import 'package:lap_timer/features/timing/presentation/live_session_notifier.dart';
import 'package:lap_timer/features/timing/presentation/live_session_state.dart';
import 'package:lap_timer/features/tracks/domain/track.dart';
import 'package:lap_timer/features/tracks/presentation/text_prompt.dart';
import 'package:lap_timer/l10n/generated/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

/// Pick track, sector layout, vehicle and compare mode, then start timing.
class NewSessionScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const NewSessionScreen({super.key});

  @override
  ConsumerState<NewSessionScreen> createState() => _NewSessionScreenState();
}

class _NewSessionScreenState extends ConsumerState<NewSessionScreen> {
  String? _trackId;
  String? _layoutId;
  VehicleType _vehicle = VehicleType.car;
  SectorCompareMode _compareMode = SectorCompareMode.bestLap;

  /// Selected rule set id; '' = no race rules (practice).
  String? _rulesId;
  final List<String> _drivers = [];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tracks = (ref.watch(tracksProvider).value ?? const <Track>[])
        .where((t) => t.startFinish != null)
        .toList();
    final track = _selectedTrack(tracks);
    final layout = _selectedLayout(track);
    final source = ref.watch(gpsSourceProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.newSessionTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Label(l10n.newSessionTrack),
          if (tracks.isEmpty) Text(l10n.newSessionNoTracks),
          DropdownButton<String>(
            isExpanded: true,
            value: track?.id,
            items: [
              for (final t in tracks)
                DropdownMenuItem(value: t.id, child: Text(t.name)),
            ],
            onChanged: (id) => setState(() {
              _trackId = id;
              _layoutId = null;
            }),
          ),
          _Label(l10n.newSessionSectors),
          DropdownButton<String?>(
            isExpanded: true,
            value: layout?.id,
            items: [
              DropdownMenuItem(child: Text(l10n.newSessionNoSectors)),
              for (final l in track?.sectorLayouts ?? const <SectorLayout>[])
                DropdownMenuItem(value: l.id, child: Text(l.name)),
            ],
            onChanged: (id) => setState(() => _layoutId = id ?? ''),
          ),
          _Label(l10n.newSessionVehicle),
          SegmentedButton<VehicleType>(
            segments: [
              ButtonSegment(
                value: VehicleType.car,
                label: Text(l10n.vehicleCar),
              ),
              ButtonSegment(
                value: VehicleType.kart,
                label: Text(l10n.vehicleKart),
              ),
              ButtonSegment(
                value: VehicleType.motorcycle,
                label: Text(l10n.vehicleMotorcycle),
              ),
              ButtonSegment(
                value: VehicleType.bicycle,
                label: Text(l10n.vehicleBicycle),
              ),
            ],
            selected: {_vehicle},
            onSelectionChanged: (v) => setState(() => _vehicle = v.single),
          ),
          _Label(l10n.newSessionCompare),
          SegmentedButton<SectorCompareMode>(
            segments: [
              ButtonSegment(
                value: SectorCompareMode.bestLap,
                label: Text(l10n.compareBestLap),
              ),
              ButtonSegment(
                value: SectorCompareMode.bestSector,
                label: Text(l10n.compareBestSector),
              ),
            ],
            selected: {_compareMode},
            onSelectionChanged: (v) => setState(() => _compareMode = v.single),
          ),
          _RulesPicker(
            selectedId: _rulesId,
            onChanged: (id) => setState(() => _rulesId = id),
          ),
          _Label(l10n.newSessionDrivers),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final (i, name) in _drivers.indexed)
                InputChip(
                  label: Text('${i + 1} · $name'),
                  onDeleted: () => setState(() => _drivers.removeAt(i)),
                ),
              ActionChip(
                avatar: const Icon(Icons.add),
                label: Text(l10n.newSessionAddDriver),
                onPressed: () => unawaited(_addDriver()),
              ),
            ],
          ),
          if (track != null && track.pitEntry == null && _rulesId != '')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(l10n.newSessionNoPitLines),
            ),
          _Label(l10n.homeGpsSourceTitle),
          Text(source?.displayName ?? l10n.homeSelectLogFirst),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: track == null || source == null
                ? null
                : () => unawaited(_start(track, layout)),
            child: Text(l10n.newSessionStart),
          ),
        ],
      ),
    );
  }

  Track? _selectedTrack(List<Track> tracks) {
    for (final t in tracks) {
      if (t.id == _trackId) return t;
    }
    return tracks.isEmpty ? null : tracks.first;
  }

  /// `_layoutId` null = use the track default; '' = no sectors.
  SectorLayout? _selectedLayout(Track? track) {
    if (track == null || _layoutId == '') return null;
    for (final l in track.sectorLayouts) {
      if (l.id == _layoutId) return l;
    }
    return _layoutId == null ? track.defaultSectorLayout : null;
  }

  Future<void> _addDriver() async {
    final l10n = AppLocalizations.of(context);
    final name = await promptForText(context, title: l10n.newSessionAddDriver);
    if (name == null || name.trim().isEmpty || !mounted) return;
    setState(() => _drivers.add(name.trim()));
  }

  RaceRules? _selectedRules() {
    final all = ref.read(raceRulesProvider).value ?? const <RaceRules>[];
    if (_rulesId == '') return null;
    for (final r in all) {
      if (r.id == _rulesId) return r;
    }
    return _rulesId == null && all.isNotEmpty ? all.first : null;
  }

  Future<void> _start(Track track, SectorLayout? layout) async {
    ref.read(pendingSessionConfigProvider.notifier).config = LiveSessionConfig(
      track: track,
      sectorLayout: layout,
      vehicleType: _vehicle,
      compareMode: _compareMode,
      raceRules: _selectedRules(),
      drivers: List.of(_drivers),
    );
    await context.push(AppRoutes.live);
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(top: 20, bottom: 6),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

/// Race rules dropdown ("No race rules" = practice, no pit mode) with a
/// shortcut to manage the rule sets.
class _RulesPicker extends ConsumerWidget {
  const _RulesPicker({required this.selectedId, required this.onChanged});

  /// null = first rule set; '' = none.
  final String? selectedId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final all = ref.watch(raceRulesProvider).value ?? const <RaceRules>[];
    final value = selectedId ?? (all.isEmpty ? '' : all.first.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Label(l10n.newSessionRules),
        Row(
          children: [
            Expanded(
              child: DropdownButton<String>(
                isExpanded: true,
                value: value,
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text(l10n.newSessionNoRules),
                  ),
                  for (final r in all)
                    DropdownMenuItem(value: r.id, child: Text(r.name)),
                ],
                onChanged: (id) => onChanged(id ?? ''),
              ),
            ),
            IconButton(
              tooltip: l10n.rulesTitle,
              icon: const Icon(Icons.tune),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const RaceRulesScreen(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
