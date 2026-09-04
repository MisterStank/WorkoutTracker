import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pet_avatar.dart';
import 'pet_models.dart';
import 'pet_palette.dart';
import 'pet_provider.dart';

/// Companion detail: bigger avatar, rename, recolour, and the accessory
/// locker (unlocked items are equippable, one per slot; locked items show
/// their unlock hint).
class PetDetailScreen extends ConsumerWidget {
  const PetDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pet = ref.watch(petProvider).valueOrNull;
    if (pet == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(pet.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Rename',
            onPressed: () => _rename(context, ref, pet),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(child: PetAvatar(pet: pet, size: 200)),
          const SizedBox(height: 16),
          Text('Colour', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final c in PetColor.values)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: GestureDetector(
                    onTap: () => ref.read(petProvider.notifier).setColor(c),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: petColorSwatch(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: pet.color == c ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Wardrobe', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _AccessoryLocker(pet: pet),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref, Pet pet) async {
    final controller = TextEditingController(text: pet.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename companion'),
        content: TextField(controller: controller, maxLength: 30, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty && name != pet.name) {
      try {
        await ref.read(petProvider.notifier).rename(name);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
          );
        }
      }
    }
  }
}

class _AccessoryLocker extends ConsumerWidget {
  const _AccessoryLocker({required this.pet});

  final Pet pet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owned = {for (final a in pet.accessories) a.accessory.code: a};
    // Group by slot for display.
    final bySlot = <String, List<PetAccessory>>{};
    for (final a in pet.accessories) {
      bySlot.putIfAbsent(a.accessory.slot, () => []).add(a);
    }

    if (pet.accessories.isEmpty) {
      return Text(
        'No accessories yet — keep training to unlock hats, collars, capes and more.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in bySlot.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(_slotLabel(entry.key), style: Theme.of(context).textTheme.labelLarge),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in entry.value)
                FilterChip(
                  label: Text(a.accessory.name),
                  selected: a.equipped,
                  onSelected: (sel) {
                    final notifier = ref.read(petProvider.notifier);
                    sel ? notifier.equip(a.accessory.id) : notifier.unequip(a.accessory.id);
                  },
                ),
            ],
          ),
        ],
        const SizedBox(height: 4),
        Text(
          '${owned.length} unlocked',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  String _slotLabel(String slot) {
    if (slot.isEmpty) return 'Other';
    return slot[0].toUpperCase() + slot.substring(1);
  }
}
