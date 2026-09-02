import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sharing/pet_share_card.dart';
import '../sharing/share_preview_sheet.dart';
import 'pet_avatar.dart';
import 'pet_detail_screen.dart';
import 'pet_models.dart';
import 'pet_onboarding_screen.dart';
import 'pet_provider.dart';

/// The app's landing screen: your companion, its mood and streak, and the
/// button that starts a workout to keep it thriving. When there's no pet yet
/// this hosts the onboarding flow instead.
class PetHomeScreen extends ConsumerStatefulWidget {
  const PetHomeScreen({super.key, required this.onStartWorkout});

  /// Switches the app shell to the workout tab.
  final VoidCallback onStartWorkout;

  @override
  ConsumerState<PetHomeScreen> createState() => _PetHomeScreenState();
}

class _PetHomeScreenState extends ConsumerState<PetHomeScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(petProvider.notifier).refresh();
    }
  }

  void _sharePet(BuildContext context, Pet pet) {
    final streak = pet.currentStreak;
    final text = streak > 0
        ? 'Meet ${pet.name} — my Gymon companion. ${pet.stageLabel}, $streak-day training streak. 💪'
        : 'Meet ${pet.name} — my Gymon companion. ${pet.stageLabel}.';
    showSharePreview(
      context,
      card: PetShareCard(pet: pet),
      filename: 'gymon-${pet.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}',
      text: text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final petAsync = ref.watch(petProvider);

    ref.listen(petProvider, (_, next) {
      final pet = next.valueOrNull;
      if (!mounted || pet == null || pet.newlyUnlocked.isEmpty) return;
      // A workout unlocks one or two things — that's the moment worth
      // celebrating. A big batch (first load of an established account, an
      // import) just gets a quiet count so we don't stack ten snackbars.
      final unlocked = pet.newlyUnlocked;
      final message = unlocked.length <= 3
          ? 'New unlock: ${unlocked.map((a) => a.accessory.name).join(', ')} 🎉'
          : '${unlocked.length} new accessories unlocked 🎉';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(petAsync.valueOrNull?.name ?? 'Companion'),
        actions: [
          if (petAsync.valueOrNull != null) ...[
            IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: 'Share ${petAsync.valueOrNull!.name}',
              onPressed: () => _sharePet(context, petAsync.valueOrNull!),
            ),
            IconButton(
              icon: const Icon(Icons.checkroom_outlined),
              tooltip: 'Details & wardrobe',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PetDetailScreen()),
              ),
            ),
          ],
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(petProvider.notifier).refresh(),
        child: petAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              const SizedBox(height: 120),
              Center(child: Text('Couldn\'t load your companion.\n${e.toString().replaceFirst('Exception: ', '')}', textAlign: TextAlign.center)),
              const SizedBox(height: 12),
              Center(child: OutlinedButton(onPressed: () => ref.read(petProvider.notifier).refresh(), child: const Text('Retry'))),
            ],
          ),
          data: (pet) => pet == null
              ? const PetOnboardingView()
              : _PetHomeView(pet: pet, onStartWorkout: widget.onStartWorkout),
        ),
      ),
    );
  }
}

class _PetHomeView extends StatelessWidget {
  const _PetHomeView({required this.pet, required this.onStartWorkout});

  final Pet pet;
  final VoidCallback onStartWorkout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 8),
        Center(child: PetAvatar(pet: pet, size: 200)),
        const SizedBox(height: 12),
        Center(
          child: Text('${pet.stageLabel} · ${_moodLabel(pet.moodState)}', style: theme.textTheme.titleMedium),
        ),
        const SizedBox(height: 16),
        _MoodBar(mood: pet.mood, state: pet.moodState),
        if (pet.isNeglected) ...[
          const SizedBox(height: 8),
          Text(
            '${pet.name} is feeling neglected. A workout will start cheering them up.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: _StatTile(label: 'Current streak', value: '${pet.currentStreak} d')),
            const SizedBox(width: 12),
            Expanded(child: _StatTile(label: 'Longest streak', value: '${pet.longestStreak} d')),
          ],
        ),
        const SizedBox(height: 12),
        _NextStageCard(pet: pet),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: onStartWorkout,
          icon: const Icon(Icons.fitness_center),
          label: Text('Train to feed ${pet.name}'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
        const SizedBox(height: 16),
        if (pet.accessories.isNotEmpty)
          Text('${pet.accessories.length} accessor${pet.accessories.length == 1 ? 'y' : 'ies'} unlocked',
              style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
      ],
    );
  }
}

String _moodLabel(MoodState s) => switch (s) {
      MoodState.happy => 'Thriving',
      MoodState.content => 'Content',
      MoodState.low => 'A bit down',
      MoodState.neglected => 'Neglected',
    };

class _MoodBar extends StatelessWidget {
  const _MoodBar({required this.mood, required this.state});

  final int mood;
  final MoodState state;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      MoodState.happy => Colors.green,
      MoodState.content => Colors.lightGreen,
      MoodState.low => Colors.orange,
      MoodState.neglected => Colors.red,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Mood', style: Theme.of(context).textTheme.labelMedium),
            Text('$mood / 100', style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(value: mood / 100, minHeight: 10, color: color),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: theme.textTheme.titleLarge),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _NextStageCard extends StatelessWidget {
  const _NextStageCard({required this.pet});

  final Pet pet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = pet.workoutsToNextStage;
    final text = remaining == null
        ? '${pet.name} has reached the final evolution stage. 🏆'
        : remaining == 0
            ? 'Next workout evolves ${pet.name}!'
            : '$remaining more workout${remaining == 1 ? '' : 's'} to the next evolution.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: theme.textTheme.bodyMedium),
    );
  }
}
