@Tags(['dump'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymon/features/pet/pet_avatar.dart';
import 'package:gymon/features/pet/pet_models.dart';

// `flutter test test/pet_avatar_dump_test.dart --run-skipped` writes a PNG of
// every species x stage x mood to build/pet-dump/ for an eyeball check.

Pet _pet(PetSpecies s, PetColor c, PetStage st, MoodState m) => Pet(
      id: 'p',
      name: 'Pixel',
      species: s,
      color: c,
      stage: st,
      stageLabel: st.name,
      mood: 50,
      moodState: m,
      currentStreak: 0,
      longestStreak: 0,
      workoutsToNextStage: 2,
      hatchedAt: null,
      appearance: const PetAppearance(bodyAssetKey: '', expressionAssetKey: '', tint: '', layers: []),
      accessories: const [],
      newlyUnlocked: const [],
    );

void main() {
  testWidgets('dump', (tester) async {
    final dir = Directory('build/pet-dump')..createSync(recursive: true);
    for (final s in PetSpecies.values) {
      for (final st in PetStage.values) {
        for (final m in MoodState.values) {
          await tester.pumpWidget(
            MediaQuery(
              data: const MediaQueryData(),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Container(
                  color: const Color(0xFFF7EFEA),
                  alignment: Alignment.center,
                  child: RepaintBoundary(child: PetAvatar(pet: _pet(s, PetColor.green, st, m), size: 220)),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 900)); // mid-blink-ish / breathing
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.descendant(of: find.byType(PetAvatar), matching: find.byType(RepaintBoundary)).first,
          );
          await tester.runAsync(() async {
            final img = await boundary.toImage(pixelRatio: 3);
            final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
            File('${dir.path}/${s.name}_${st.name}_${m.name}.png').writeAsBytesSync(bytes!.buffer.asUint8List());
          });
        }
      }
    }
    // contact sheet: one colour swatch strip of an adult per species/mood
    for (final c in PetColor.values) {
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Container(
            color: const Color(0xFFF7EFEA),
            alignment: Alignment.center,
            child: RepaintBoundary(child: PetAvatar(pet: _pet(PetSpecies.sprout, c, PetStage.adult, MoodState.content), size: 220)),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final b = tester.renderObject<RenderRepaintBoundary>(
        find.descendant(of: find.byType(PetAvatar), matching: find.byType(RepaintBoundary)).first,
      );
      await tester.runAsync(() async {
        final img = await b.toImage(pixelRatio: 3);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        File('${dir.path}/_colour_${c.name}.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }
    await tester.pumpWidget(const SizedBox());
  });
}
