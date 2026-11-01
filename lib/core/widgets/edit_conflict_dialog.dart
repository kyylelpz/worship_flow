import 'package:flutter/material.dart';
import '../models/edit_conflict.dart';

/// Reload is explicitly destructive to the local draft; dismissals keep it.
Future<bool> confirmConflictReload(
        BuildContext context, EditConflict conflict) async =>
    await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text(conflict.deleted
                  ? '${conflict.record} deleted'
                  : '${conflict.record} changed'),
              content: Text(
                  '${conflict.toString()} Reload Latest discards your local edits and loads the current record. A deleted record cannot be saved again.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel')),
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Keep Editing')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Reload Latest')),
              ],
            )) ==
    true;
