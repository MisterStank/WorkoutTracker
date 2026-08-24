import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'fitness_profile_models.dart';
import 'fitness_profile_provider.dart';
import 'program_review_screen.dart';

/// Collects goal/experience/days-per-week/equipment/exclusions, then
/// generates a full multi-day split from them. Pre-fills from whatever
/// profile the user last saved, if any, so regenerating a program doesn't
/// mean re-entering everything.
class FitnessProfileScreen extends ConsumerStatefulWidget {
  const FitnessProfileScreen({super.key});

  @override
  ConsumerState<FitnessProfileScreen> createState() => _FitnessProfileScreenState();
}

class _FitnessProfileScreenState extends ConsumerState<FitnessProfileScreen> {
  FitnessGoal _goal = FitnessGoal.generalFitness;
  ExperienceLevel _experience = ExperienceLevel.beginner;
  int _daysPerWeek = 3;
  final Set<String> _equipment = {'barbell', 'dumbbell', 'bodyweight', 'cable', 'machine'};
  final Set<String> _avoid = {};
  bool _loading = true;
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _loadExistingProfile();
  }

  Future<void> _loadExistingProfile() async {
    try {
      final profile = await ref.read(fitnessProfileRepositoryProvider).myFitnessProfile();
      if (profile != null && mounted) {
        setState(() {
          _goal = profile.goal;
          _experience = profile.experienceLevel;
          _daysPerWeek = profile.daysPerWeek;
          _equipment
            ..clear()
            ..addAll(profile.equipmentAccess);
          _avoid
            ..clear()
            ..addAll(profile.avoidMuscleGroups);
        });
      }
    } catch (_) {
      // No saved profile yet, or a transient fetch error — the form's
      // sensible defaults are a fine starting point either way.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generate() async {
    setState(() => _generating = true);
    try {
      final repo = ref.read(fitnessProfileRepositoryProvider);
      await repo.saveFitnessProfile(
        goal: _goal,
        experienceLevel: _experience,
        daysPerWeek: _daysPerWeek,
        equipmentAccess: _equipment.toList(),
        avoidMuscleGroups: _avoid.toList(),
      );
      final program = await repo.generateProgram();
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProgramReviewScreen(program: program)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not generate a program: $e')));
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Personalize a program')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Goal', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          DropdownButtonFormField<FitnessGoal>(
            initialValue: _goal,
            items: FitnessGoal.values.map((g) => DropdownMenuItem(value: g, child: Text(g.label))).toList(),
            onChanged: (g) => setState(() => _goal = g ?? _goal),
          ),
          const SizedBox(height: 20),
          Text('Experience level', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          DropdownButtonFormField<ExperienceLevel>(
            initialValue: _experience,
            items: ExperienceLevel.values.map((e) => DropdownMenuItem(value: e, child: Text(e.label))).toList(),
            onChanged: (e) => setState(() => _experience = e ?? _experience),
          ),
          const SizedBox(height: 20),
          Text('Days per week', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: _daysPerWeek > 1 ? () => setState(() => _daysPerWeek--) : null,
              ),
              Text('$_daysPerWeek', style: Theme.of(context).textTheme.titleLarge),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: _daysPerWeek < 6 ? () => setState(() => _daysPerWeek++) : null,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Equipment you have access to', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: availableEquipment.map((eq) {
              final selected = _equipment.contains(eq);
              return FilterChip(
                label: Text(eq),
                selected: selected,
                onSelected: (v) => setState(() => v ? _equipment.add(eq) : _equipment.remove(eq)),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          Text('Areas to avoid (optional)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            "Injuries or trouble spots — we'll skip exercises that target these.",
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: availableMuscleGroups.map((mg) {
              final selected = _avoid.contains(mg);
              return FilterChip(
                label: Text(mg),
                selected: selected,
                onSelected: (v) => setState(() => v ? _avoid.add(mg) : _avoid.remove(mg)),
              );
            }).toList(),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: _equipment.isEmpty || _generating ? null : _generate,
            icon: _generating
                ? SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Theme.of(context).colorScheme.onPrimary),
                  )
                : const Icon(Icons.auto_awesome),
            label: Text(_generating ? 'Generating…' : 'Generate program'),
          ),
        ],
      ),
    );
  }
}
