import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pet_avatar.dart';
import 'pet_models.dart';
import 'pet_provider.dart';

/// Shown on the pet home tab when the user has no pet yet, and as a step of
/// the first-run flow. Picking a species, colour and name creates the
/// companion; the surrounding [petProvider] then flips to showing it, and
/// [onCreated] fires (the onboarding flow uses it to advance to the next
/// step).
class PetOnboardingView extends ConsumerStatefulWidget {
  const PetOnboardingView({super.key, this.onCreated, this.showIntro = true});

  final VoidCallback? onCreated;

  /// The "Meet your companion" heading + blurb. Hidden when a parent screen
  /// already provides that framing (the onboarding flow does).
  final bool showIntro;

  @override
  ConsumerState<PetOnboardingView> createState() => _PetOnboardingViewState();
}

class _PetOnboardingViewState extends ConsumerState<PetOnboardingView> {
  final _nameController = TextEditingController();
  PetSpecies _species = PetSpecies.sprout;
  PetColor _color = PetColor.green;
  bool _submitting = false;

  static const _speciesLabels = {
    PetSpecies.sprout: 'Sprout',
    PetSpecies.ember: 'Ember',
    PetSpecies.pebble: 'Pebble',
    PetSpecies.drift: 'Drift',
  };

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Pet get _preview => Pet(
        id: 'preview',
        name: _nameController.text.trim().isEmpty ? 'Your companion' : _nameController.text.trim(),
        species: _species,
        color: _color,
        stage: PetStage.egg,
        stageLabel: 'Egg',
        mood: 60,
        moodState: MoodState.content,
        currentStreak: 0,
        longestStreak: 0,
        workoutsToNextStage: 5,
        hatchedAt: null,
        appearance: const PetAppearance(bodyAssetKey: '', expressionAssetKey: '', tint: '', layers: []),
        accessories: const [],
        newlyUnlocked: const [],
      );

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Give your companion a name')));
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref.read(petProvider.notifier).createPet(name: name, species: _species, color: _color);
      widget.onCreated?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is Exception ? e.toString().replaceFirst('Exception: ', '') : 'Something went wrong')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 8),
        if (widget.showIntro) ...[
          Text('Meet your companion', style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(
            'It hatches when you finish your first workout, and grows the more consistently you train.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
        ],
        Center(child: PetAvatar(pet: _preview, size: 180)),
        const SizedBox(height: 24),
        Text('Species', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final s in PetSpecies.values)
              ChoiceChip(
                label: Text(_speciesLabels[s]!),
                selected: _species == s,
                onSelected: (_) => setState(() => _species = s),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Text('Colour', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final c in PetColor.values)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: petColorSwatch(c),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _color == c ? theme.colorScheme.onSurface : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _nameController,
          maxLength: 30,
          decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Hatch your companion'),
        ),
      ],
    );
  }
}

Color petColorSwatch(PetColor c) {
  switch (c) {
    case PetColor.green:
      return const Color(0xFF4CAF7D);
    case PetColor.red:
      return const Color(0xFFE0574B);
    case PetColor.blue:
      return const Color(0xFF4C8DE0);
    case PetColor.amber:
      return const Color(0xFFE0A94C);
    case PetColor.violet:
      return const Color(0xFF9B6BE0);
  }
}
