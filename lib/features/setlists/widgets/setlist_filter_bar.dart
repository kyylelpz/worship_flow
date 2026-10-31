import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/setlist_providers.dart';

class SetlistFilterBar extends ConsumerWidget {
  const SetlistFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(setlistFilterProvider);
    final theme = Theme.of(context);

    Widget chip(SetlistFilter filter, String label) {
      final selected = current == filter;
      return ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) =>
            ref.read(setlistFilterProvider.notifier).select(filter),
        labelStyle: theme.textTheme.labelLarge?.copyWith(
          color: selected
              ? theme.colorScheme.onPrimary
              : theme.colorScheme.onSurface,
        ),
        selectedColor: theme.colorScheme.primary,
        showCheckmark: false,
        side: BorderSide(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outline.withValues(alpha: 0.7),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip(SetlistFilter.upcoming, 'Upcoming'),
          const SizedBox(width: 8),
          chip(SetlistFilter.previous, 'Previous'),
          const SizedBox(width: 8),
          chip(SetlistFilter.drafts, 'Drafts'),
        ],
      ),
    );
  }
}
