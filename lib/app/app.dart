import '../core/preferences/user_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/router/app_router.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/theme_providers.dart';

class WorshipFlowApp extends ConsumerWidget {
  const WorshipFlowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final restoringPreferences =
        ref.watch(userPreferencesProvider.select((s) => s.loading));
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'WorshipFlow',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode,
      routerConfig: router,
      builder: (context, child) => Stack(fit: StackFit.expand, children: [
        // Keep the router mounted while hiding default-valued account content.
        Offstage(
            offstage: restoringPreferences,
            child: TickerMode(
                enabled: !restoringPreferences,
                child: child ?? const SizedBox.shrink())),
        if (restoringPreferences)
          const ColoredBox(
              color: Color(0xFFF5F5F5),
              child: Center(child: CircularProgressIndicator())),
      ]),
    );
  }
}
