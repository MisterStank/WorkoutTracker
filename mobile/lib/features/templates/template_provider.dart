import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_provider.dart';
import 'template_models.dart';
import 'template_repository.dart';

final templateRepositoryProvider = Provider<TemplateRepository>((ref) {
  return TemplateRepository(ref.watch(graphQLClientProvider));
});

/// All of the user's templates, id-keyed, so the active-workout screen can
/// resolve a workout's templateId to its planned exercise list without a
/// separate fetch every time.
final templateCatalogProvider = FutureProvider<Map<String, WorkoutTemplate>>((ref) async {
  final templates = await ref.watch(templateRepositoryProvider).list();
  return {for (final t in templates) t.id: t};
});
