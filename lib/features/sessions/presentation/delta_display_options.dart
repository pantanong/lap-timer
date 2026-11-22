import 'package:lap_timer/features/timing/presentation/live_session_state.dart';
import 'package:lap_timer/l10n/generated/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

/// New Session section: how long the big number shows sector and lap gaps.
class DeltaDisplayOptions extends StatelessWidget {
  /// Creates the section.
  const DeltaDisplayOptions({
    required this.settings,
    required this.onChanged,
    super.key,
  });

  /// Current settings.
  final DeltaDisplaySettings settings;

  /// Called with new settings.
  final ValueChanged<DeltaDisplaySettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.gapDisplayTitle,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            _SecondsStepper(
              label: l10n.gapDisplaySector,
              value: settings.sectorHold,
              min: 1,
              max: 10,
              onChanged: (v) => onChanged(
                DeltaDisplaySettings(
                  sectorHold: v,
                  lastSectorHold: settings.lastSectorHold,
                  lapHold: settings.lapHold,
                ),
              ),
            ),
            _SecondsStepper(
              label: l10n.gapDisplayLastSector,
              value: settings.lastSectorHold,
              min: 0,
              max: 5,
              onChanged: (v) => onChanged(
                DeltaDisplaySettings(
                  sectorHold: settings.sectorHold,
                  lastSectorHold: v,
                  lapHold: settings.lapHold,
                ),
              ),
            ),
            _SecondsStepper(
              label: l10n.gapDisplayLap,
              value: settings.lapHold,
              min: 1,
              max: 10,
              onChanged: (v) => onChanged(
                DeltaDisplaySettings(
                  sectorHold: settings.sectorHold,
                  lastSectorHold: settings.lastSectorHold,
                  lapHold: v,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecondsStepper extends StatelessWidget {
  const _SecondsStepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final Duration value;
  final int min;
  final int max;
  final ValueChanged<Duration> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final seconds = value.inSeconds;
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          tooltip: '−',
          icon: const Icon(Icons.remove),
          onPressed: seconds <= min
              ? null
              : () => onChanged(Duration(seconds: seconds - 1)),
        ),
        SizedBox(
          width: 44,
          child: Text(
            l10n.unitSeconds(seconds),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          tooltip: '+',
          icon: const Icon(Icons.add),
          onPressed: seconds >= max
              ? null
              : () => onChanged(Duration(seconds: seconds + 1)),
        ),
      ],
    );
  }
}
