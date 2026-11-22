import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lap_timer/app/infrastructure_providers.dart';
import 'package:lap_timer/core/ui/page_padding.dart';
import 'package:lap_timer/features/race/domain/race_rules.dart';
import 'package:lap_timer/features/tracks/presentation/text_prompt.dart';
import 'package:lap_timer/l10n/generated/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

/// List of race rule sets; tap one to edit it, + to add one.
class RaceRulesScreen extends ConsumerWidget {
  /// Creates the screen.
  const RaceRulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final all = ref.watch(raceRulesProvider).value ?? const <RaceRules>[];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.rulesTitle)),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text(l10n.rulesNew),
        onPressed: () => unawaited(_create(context, ref)),
      ),
      body: ListView(
        padding: pagePadding(context, hasFloatingButton: true),
        children: [
          for (final rules in all)
            Card(
              child: ListTile(
                title: Text(rules.name),
                subtitle: Text(
                  l10n.rulesSummary(
                    rules.pitSpeedLimitKmh.round(),
                    rules.minimumPitTime.inSeconds,
                    rules.requiredPitStops,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RaceRulesEditScreen(rules: rules),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final name = await promptForText(context, title: l10n.rulesNew);
    if (name == null || name.trim().isEmpty) return;
    final id = 'rules-${ref.read(clockProvider).now().microsecondsSinceEpoch}';
    await ref
        .read(raceRulesRepositoryProvider)
        .save(RaceRules(id: id, name: name.trim()));
  }
}

/// Form to edit one rule set. Saves when the user taps Save.
class RaceRulesEditScreen extends ConsumerStatefulWidget {
  /// Edits [rules].
  const RaceRulesEditScreen({required this.rules, super.key});

  /// The rule set being edited.
  final RaceRules rules;

  @override
  ConsumerState<RaceRulesEditScreen> createState() =>
      _RaceRulesEditScreenState();
}

class _RaceRulesEditScreenState extends ConsumerState<RaceRulesEditScreen> {
  late final Map<String, TextEditingController> _fields = {
    'name': TextEditingController(text: widget.rules.name),
    'limit': _num(widget.rules.pitSpeedLimitKmh),
    'target': _num(widget.rules.pitTargetSpeedKmh),
    'minPit': _num(widget.rules.minimumPitTime.inSeconds),
    'margin': _num(widget.rules.pitTimeSafetyMargin.inSeconds),
    'hold': _num(widget.rules.pitResultHold.inSeconds),
    'stops': _num(widget.rules.requiredPitStops),
    'resume': _num(widget.rules.resumeSpeedKmh),
  };

  static TextEditingController _num(num value) =>
      TextEditingController(text: value.toStringAsFixed(0));

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  double _read(String key, double fallback) =>
      double.tryParse(_fields[key]?.text.trim() ?? '') ?? fallback;

  Future<void> _save() async {
    final r = widget.rules;
    final updated = r.copyWith(
      name: _fields['name']?.text.trim(),
      pitSpeedLimitKmh: _read('limit', r.pitSpeedLimitKmh),
      pitTargetSpeedKmh: _read('target', r.pitTargetSpeedKmh),
      minimumPitTime: Duration(
        seconds: _read('minPit', r.minimumPitTime.inSeconds.toDouble()).round(),
      ),
      pitTimeSafetyMargin: Duration(
        seconds: _read(
          'margin',
          r.pitTimeSafetyMargin.inSeconds.toDouble(),
        ).round(),
      ),
      pitResultHold: Duration(
        seconds: _read('hold', r.pitResultHold.inSeconds.toDouble()).round(),
      ),
      requiredPitStops: _read('stops', r.requiredPitStops.toDouble()).round(),
      resumeSpeedKmh: _read('resume', r.resumeSpeedKmh),
    );
    await ref.read(raceRulesRepositoryProvider).save(updated);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    if (!await confirm(context, l10n.rulesDeleteConfirm)) return;
    await ref.read(raceRulesRepositoryProvider).delete(widget.rules.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget numberField(String key, String label) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _fields[key],
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.rules.name),
        actions: [
          IconButton(
            tooltip: l10n.actionDelete,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => unawaited(_delete()),
          ),
        ],
      ),
      body: ListView(
        padding: pagePadding(context, hasFloatingButton: true),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: _fields['name'],
              decoration: InputDecoration(labelText: l10n.rulesName),
            ),
          ),
          numberField('limit', l10n.rulesSpeedLimit),
          numberField('target', l10n.rulesTargetSpeed),
          numberField('minPit', l10n.rulesMinimumPitTime),
          numberField('margin', l10n.rulesSafetyMargin),
          numberField('hold', l10n.rulesResultHold),
          numberField('stops', l10n.rulesRequiredStops),
          numberField('resume', l10n.rulesResumeSpeed),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => unawaited(_save()),
            child: Text(l10n.actionSave),
          ),
        ],
      ),
    );
  }
}
