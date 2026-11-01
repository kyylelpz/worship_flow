import '../preferences/user_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController([super.state = ThemeMode.light]);

  void setMode(ThemeMode mode) => state = mode;

  void toggle() {
    state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
  }

  void reset() => state = ThemeMode.light;
}

final themeModeProvider = StateNotifierProvider<ThemeModeController, ThemeMode>(
  (ref) {
    ref.watch(userPreferencesProvider.select((s) => (s.uid, s.loading)));
    final owner = ref.read(userPreferencesProvider.notifier);
    final controller =
        ThemeModeController(ref.read(userPreferencesProvider).value.theme);
    controller.addListener(owner.setTheme, fireImmediately: false);
    return controller;
  },
);
