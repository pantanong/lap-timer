import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lap_timer/app/infrastructure_providers.dart';
import 'package:lap_timer/features/brake_coach/domain/brake_profile.dart';
import 'package:lap_timer/features/gps/gps_providers.dart';
import 'package:lap_timer/features/sessions/domain/session.dart';
import 'package:lap_timer/l10n/generated/app_localizations.dart';
import 'package:lap_timer/theme/app_colors.dart';
import 'package:material_ui/material_ui.dart';

/// What the user picked for the brake coach on the New Session screen.
@immutable
class BrakeCoachChoice {
  /// Creates a choice; defaults = off, learn 3 laps, Method 1, 0.7 s.
  const BrakeCoachChoice({
    this.enabled = false,
    this.profileId,
    this.learningLaps = 3,
    this.method = BrakeLearningMethod.fastestLap,
    this.leadTimeMs = 700,
  });

  /// Brake coach on.
  final bool enabled;

  /// Saved profile to use; null = learn during this session.
  final String? profileId;

  /// Laps to learn from.
  final int learningLaps;

  /// Method 1 or 2.
  final BrakeLearningMethod method;

  /// How early red appears, milliseconds.
  final int leadTimeMs;

  /// Returns a copy with the given fields replaced. [clearProfile] switches
  /// back to "learn from this session".
  BrakeCoachChoice copyWith({
    bool? enabled,
    String? profileId,
    bool clearProfile = false,
    int? learningLaps,
    BrakeLearningMethod? method,
    int? leadTimeMs,
  }) => BrakeCoachChoice(
    enabled: enabled ?? this.enabled,
    profileId: clearProfile ? null : profileId ?? this.profileId,
    learningLaps: learningLaps ?? this.learningLaps,
    method: method ?? this.method,
    leadTimeMs: leadTimeMs ?? this.leadTimeMs,
  );
}

/// Brake coach section of the New Session screen. Never shown for
/// bicycles (the caller hides it).
class BrakeCoachOptions extends ConsumerWidget {
  /// Creates the section.
  const BrakeCoachOptions({
    required this.trackId,
    required this.vehicleType,
    required this.choice,
    required this.onChanged,
    super.key,
  });

  /// Selected track (profiles are per track and vehicle).
  final String trackId;

  /// Selected vehicle.
  final VehicleType vehicleType;

  /// Current choice.
  final BrakeCoachChoice choice;

  /// Called with the new choice.
  final ValueChanged<BrakeCoachChoice> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final profiles = [
      for (final p
          in ref.watch(brakeProfilesProvider).value ?? const <BrakeProfile>[])
        if (p.trackId == trackId && p.vehicleType == vehicleType) p,
    ];
    final validProfile = profiles.any((p) => p.id == choice.profileId)
        ? choice.profileId
        : null;
    final phoneGps = ref.watch(gpsSourceChoiceProvider) is PhoneGpsChoice;
    return Card(
      margin: const EdgeInsets.only(top: 20),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.brakeCoachTitle),
              subtitle: Text(l10n.brakeCoachEnable),
              value: choice.enabled,
              onChanged: (v) => onChanged(choice.copyWith(enabled: v)),
            ),
            if (choice.enabled) ...[
              DropdownButton<String?>(
                isExpanded: true,
                value: validProfile,
                items: [
                  DropdownMenuItem(child: Text(l10n.brakeCoachLearnNew)),
                  for (final p in profiles)
                    DropdownMenuItem(value: p.id, child: Text(p.name)),
                ],
                onChanged: (id) => onChanged(
                  id == null
                      ? choice.copyWith(clearProfile: true)
                      : choice.copyWith(profileId: id),
                ),
              ),
              if (validProfile == null) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.brakeCoachLearningLaps(choice.learningLaps),
                      ),
                    ),
                    IconButton(
                      tooltip: '−',
                      icon: const Icon(Icons.remove),
                      onPressed: choice.learningLaps <= 1
                          ? null
                          : () => onChanged(
                              choice.copyWith(
                                learningLaps: choice.learningLaps - 1,
                              ),
                            ),
                    ),
                    IconButton(
                      tooltip: '+',
                      icon: const Icon(Icons.add),
                      onPressed: choice.learningLaps >= 10
                          ? null
                          : () => onChanged(
                              choice.copyWith(
                                learningLaps: choice.learningLaps + 1,
                              ),
                            ),
                    ),
                  ],
                ),
                SegmentedButton<BrakeLearningMethod>(
                  segments: [
                    ButtonSegment(
                      value: BrakeLearningMethod.fastestLap,
                      label: Text(l10n.brakeMethodFastest),
                    ),
                    ButtonSegment(
                      value: BrakeLearningMethod.deepestValid,
                      label: Text(l10n.brakeMethodDeepest),
                    ),
                  ],
                  selected: {choice.method},
                  onSelectionChanged: (m) =>
                      onChanged(choice.copyWith(method: m.single)),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                l10n.brakeCoachLeadTime(
                  (choice.leadTimeMs / 1000).toStringAsFixed(1),
                ),
              ),
              Slider(
                value: choice.leadTimeMs.toDouble(),
                min: 0,
                max: 1500,
                divisions: 15,
                label: '${(choice.leadTimeMs / 1000).toStringAsFixed(1)} s',
                onChanged: (v) =>
                    onChanged(choice.copyWith(leadTimeMs: v.round())),
              ),
              if (phoneGps)
                Text(
                  l10n.brakeCoachPhoneGpsWarning,
                  style: TextStyle(color: colors.warning),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
