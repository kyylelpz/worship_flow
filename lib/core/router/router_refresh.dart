import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_providers.dart';
import '../models/session_state.dart';

/// A [Listenable] that fires whenever the session's *routing-relevant* fields
/// change, so GoRouter can re-evaluate redirects without rebuilding the router.
class RouterRefresh extends ChangeNotifier {
  RouterRefresh(Ref ref) {
    ref.listen(
      sessionProvider,
      (previous, next) {
        final prevKey = _key(previous);
        final nextKey = _key(next);
        if (prevKey != nextKey) notifyListeners();
      },
    );
  }

  static String _key(SessionState? s) {
    if (s == null) return 'null';
    return '${s.user?.id ?? ''}|${s.selectedGroupId ?? ''}';
  }
}