import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/preferences/user_preferences.dart';

/// Personal offsets by account/arrangement; never written to shared data.
/// Retains the StateController API used by existing controls.
final personalTransposeProvider =
    StateNotifierProvider.family<StateController<int>, int, String>((ref, id) {
  ref.watch(userPreferencesProvider.select((s) => (s.uid, s.loading)));
  final owner = ref.read(userPreferencesProvider.notifier);
  final controller =
      StateController(ref.read(userPreferencesProvider).value.offsets[id] ?? 0);
  controller.addListener((value) => owner.setOffset(id, value),
      fireImmediately: false);
  return controller;
});
