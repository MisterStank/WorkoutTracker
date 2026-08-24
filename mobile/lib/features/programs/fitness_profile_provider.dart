import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_provider.dart';
import 'fitness_profile_repository.dart';

final fitnessProfileRepositoryProvider = Provider<FitnessProfileRepository>((ref) {
  return FitnessProfileRepository(ref.watch(graphQLClientProvider));
});
