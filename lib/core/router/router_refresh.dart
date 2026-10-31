import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A [Listenable] that fires whenever a watched provider changes, so GoRouter
/// can re-evaluate redirects without the router being rebuilt entirely.
class RouterRefresh extends ChangeNotifier {
  RouterRefresh(Ref ref) {
    ref.listen(sessionRefreshSignalProvider, (_, __) => notifyListeners());
  }
}

/// A simple integer that any session-related controller can bump to force
/// GoRouter's redirect to run again.
final sessionRefreshSignalProvider = StateProvider<int>((ref) => 0);