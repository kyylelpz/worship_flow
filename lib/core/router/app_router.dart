import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/screens/login_screen.dart';
import '../../features/groups/screens/group_members_screen.dart';
import '../../features/groups/screens/group_selection_screen.dart';
import '../../features/profile/screens/chart_settings_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/setlists/screens/setlist_details_screen.dart';
import '../../features/setlists/screens/setlist_editor_screen.dart';
import '../../features/setlists/screens/setlists_screen.dart';
import '../../features/songs/screens/song_details_screen.dart';
import '../../features/songs/screens/song_editor_screen.dart';
import '../../features/songs/screens/song_library_screen.dart';
import '../models/session_state.dart';
import 'route_paths.dart';
import 'router_refresh.dart';

/// Session provider is defined here (not in auth_providers) so that the router
/// and auth layer can both depend on it without a circular import.
///
/// The actual controller implementation is injected from auth_providers when
/// the app starts, but we declare the type here to keep the router self-contained.
class SessionController extends StateNotifier<SessionState> {
  SessionController(super.state);

  void setUser(SessionState Function(SessionState) transform) {
    state = transform(state);
  }
}

final sessionProvider =
    StateNotifierProvider<SessionController, SessionState>((ref) {
  // Phase 1 placeholder — replaced by auth_providers.dart override at startup.
  return SessionController(const SessionState());
});

/// The GoRouter itself. Rebuilt when session changes so redirects re-run.
final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: RoutePaths.login,
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final loc = state.matchedLocation;
      final loggingIn = loc == RoutePaths.login;
      final choosingGroup = loc == RoutePaths.groups;

      if (!session.isAuthenticated) {
        return loggingIn ? null : RoutePaths.login;
      }

      if (!session.hasGroup && !choosingGroup) {
        return RoutePaths.groups;
      }

      if (session.hasGroup && (loggingIn || choosingGroup)) {
        return RoutePaths.setlists;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: RoutePaths.login,
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: RoutePaths.groups,
        builder: (_, __) => const GroupSelectionScreen(),
        routes: [
          GoRoute(
            path: ':groupId/members',
            builder: (_, state) => GroupMembersScreen(
              groupId: state.pathParameters['groupId']!,
            ),
          ),
        ],
      ),
      GoRoute(
        path: RoutePaths.setlists,
        builder: (_, __) => const SetlistsScreen(),
      ),
      GoRoute(
        path: RoutePaths.setlistDetails,
        builder: (_, state) => SetlistDetailsScreen(
          setlistId: state.pathParameters['setlistId']!,
        ),
        routes: [
          GoRoute(
            path: 'edit',
            builder: (_, state) => SetlistEditorScreen(
              setlistId: state.pathParameters['setlistId']!,
            ),
          ),
          GoRoute(
            path: 'rehearse',
            redirect: (_, state) => RoutePaths.setlistDetailsFor(
                state.pathParameters['setlistId']!),
          ),
          GoRoute(
            path: 'live',
            redirect: (_, state) => RoutePaths.setlistDetailsFor(
                state.pathParameters['setlistId']!),
          ),
        ],
      ),
      GoRoute(
        path: RoutePaths.songs,
        builder: (_, __) => const SongLibraryScreen(),
        routes: [
          GoRoute(
            path: ':songId',
            builder: (_, state) => SongDetailsScreen(
              songId: state.pathParameters['songId']!,
            ),
            routes: [
              GoRoute(
                path: 'edit',
                builder: (_, state) => SongEditorScreen(
                  songId: state.pathParameters['songId']!,
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: RoutePaths.profile,
        builder: (_, __) => const ProfileScreen(),
        routes: [
          GoRoute(
            path: 'chart-settings',
            builder: (_, __) => const ChartSettingsScreen(),
          ),
        ],
      ),
    ],
  );
});
