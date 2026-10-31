import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/models/setlist.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';

class SetlistCard extends ConsumerWidget {
  const SetlistCard({super.key, required this.setlist});

  final Setlist setlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dateLabel =
        DateFormat('EEE, MMM d · h:mm a').format(setlist.serviceDateTime);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push(RoutePaths.setlistDetailsFor(setlist.id)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      setlist.name,
                      style: theme.textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusChip(setlist: setlist),
                ],
              ),
              const SizedBox(height: 6),
              Text(dateLabel, style: theme.textTheme.bodySmall),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(
                    Icons.music_note_rounded,
                    size: 16,
                    color: AppColors.lightSecondaryText,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${setlist.songCount} '
                    '${setlist.songCount == 1 ? "song" : "songs"}',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (setlist.hasDraftChanges) ...[
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Unpublished changes',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.warning,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.setlist});

  final Setlist setlist;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPublished = setlist.status == SetlistStatus.published;
    final color = isPublished ? AppColors.success : AppColors.warning;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isPublished ? 'Published' : 'Draft',
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
