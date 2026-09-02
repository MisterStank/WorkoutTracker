import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymon/features/workout/superset_provider.dart';

// Regression test for a real bug found in QA: ActiveSupersetsNotifier.group()
// used to generate the ad-hoc supersetId as a plain string
// ('adhoc-<timestamp>-<counter>'), but the logSet mutation's supersetId
// argument is typed UUID! server-side — every ad-hoc superset set-log
// crashed with "invalid UUID length: 24". Fixed by generating a real v4
// UUID instead; this test locks that in.
final _uuidV4Pattern = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$', caseSensitive: false);

void main() {
  test('group() assigns a real v4 UUID as the supersetId, not a plain string', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(activeSupersetsProvider.notifier).group(['ex-1', 'ex-2']);
    final state = container.read(activeSupersetsProvider);

    final supersetId = state['ex-1'];
    expect(supersetId, isNotNull);
    expect(_uuidV4Pattern.hasMatch(supersetId!), isTrue, reason: 'supersetId must be a real UUID — the GraphQL logSet mutation rejects anything else');
  });

  test('group() assigns the same supersetId to every grouped exercise', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(activeSupersetsProvider.notifier).group(['ex-1', 'ex-2', 'ex-3']);
    final state = container.read(activeSupersetsProvider);

    expect(state['ex-1'], equals(state['ex-2']));
    expect(state['ex-2'], equals(state['ex-3']));
  });

  test('grouping fewer than two exercises is a no-op', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(activeSupersetsProvider.notifier).group(['ex-1']);
    expect(container.read(activeSupersetsProvider), isEmpty);
  });

  test('two separate group() calls produce two distinct superset ids', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(activeSupersetsProvider.notifier);
    notifier.group(['ex-1', 'ex-2']);
    notifier.group(['ex-3', 'ex-4']);
    final state = container.read(activeSupersetsProvider);

    expect(state['ex-1'], isNot(equals(state['ex-3'])));
  });

  test('ungroup() removes only the given exercise', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(activeSupersetsProvider.notifier);
    notifier.group(['ex-1', 'ex-2']);
    notifier.ungroup('ex-1');
    final state = container.read(activeSupersetsProvider);

    expect(state.containsKey('ex-1'), isFalse);
    expect(state.containsKey('ex-2'), isTrue);
  });

  test('reset() clears every grouping', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(activeSupersetsProvider.notifier);
    notifier.group(['ex-1', 'ex-2']);
    notifier.reset();

    expect(container.read(activeSupersetsProvider), isEmpty);
  });

  test('supersetIdFor returns null for an exercise not in any superset', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(activeSupersetsProvider.notifier).group(['ex-1', 'ex-2']);
    expect(container.read(activeSupersetsProvider.notifier).supersetIdFor('ex-99'), isNull);
  });
}
