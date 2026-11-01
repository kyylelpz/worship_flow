import '../../features/rehearsal/services/rehearsal_metronome.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../firebase/navigation_resume.dart';
import 'package:flutter/material.dart';
import '../../features/profile/screens/profile_completion_screen.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/providers/auth_providers.dart' as auth;
import '../../features/auth/screens/login_screen.dart';
import '../../features/groups/screens/group_members_screen.dart';
import '../../features/groups/screens/group_selection_screen.dart';
import '../../features/profile/screens/chart_settings_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/rehearsal/screens/rehearsal_screen.dart';
import '../../features/setlists/screens/setlist_editor_screen.dart';
import '../../features/setlists/screens/setlists_screen.dart';
import '../../features/songs/screens/song_details_screen.dart';
import '../../features/songs/screens/song_editor_screen.dart';
import '../../features/songs/screens/song_library_screen.dart';
import '../../features/songs/providers/song_providers.dart';
import '../models/session_state.dart';
import 'route_paths.dart';
import 'router_refresh.dart';

/// Legacy router session controller retained for API compatibility.
/// Active routing uses the auth layer's session provider below.
class SessionController extends StateNotifier<SessionState> {
  SessionController(super.state);

  void setUser(SessionState Function(SessionState) transform) {
    state = transform(state);
  }
}

final sessionProvider =
StateNotifierProvider<SessionController, SessionState>((ref) {
  // Legacy provider; authentication and routing use auth.sessionProvider.
  return SessionController(const SessionState());
});

/// The GoRouter refreshes redirects when the auth session changes.
final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = RouterRefresh(ref);
  ref.onDispose(refresh.dispose);
  String? resumedUid;

  return GoRouter(
    observers: [ref.read(rehearsalRouteObserverProvider)],
    initialLocation: RoutePaths.login,
    refreshListenable: refresh,
    redirect: (context, state) async {
      final session = ref.read(auth.sessionProvider);
      final loc = state.matchedLocation;
      final loggingIn = loc == RoutePaths.login;
      final choosingGroup = loc == RoutePaths.groups;

      if (session.isRestoring) {
        return loc == RoutePaths.sessionLoading
            ? null
            : RoutePaths.sessionLoading;
      }
      if (!session.isAuthenticated) {
        resumedUid = null;
        return loggingIn ? null : RoutePaths.login;
      }

      if (session.user?.profileComplete != true) {
        return loc == RoutePaths.profileComplete
            ? null
            : RoutePaths.profileComplete;
      }
      final resume = ref.read(sessionResumeProvider);
      if (resume.isLoading ||
          resume.hasError ||
          resume.valueOrNull?.uid != session.user!.id) {
        return loc == RoutePaths.sessionLoading
            ? null
            : RoutePaths.sessionLoading;
      }
      if (resumedUid != session.user!.id) {
        resumedUid = session.user!.id;
        final saved = resume.valueOrNull?.location;
        if (saved != null) {
          ref.read(auth.sessionProvider.notifier).selectGroup(saved.groupId);
          return saved.setlistId == null
              ? RoutePaths.setlists
              : RoutePaths.setlistRehearsalFor(saved.setlistId!);
        }
      }
      if (loc == RoutePaths.profileComplete ||
          loc == RoutePaths.sessionLoading) {
        return session.hasGroup ? RoutePaths.setlists : RoutePaths.groups;
      }
      if (!session.hasGroup && !choosingGroup && loc != RoutePaths.profile) {
        return RoutePaths.groups;
      }

      if (session.hasGroup && (loggingIn || choosingGroup)) {
        return RoutePaths.setlists;
      }

      final managingSong = loc == RoutePaths.songCreate ||
          (loc.startsWith('${RoutePaths.songs}/') && loc.endsWith('/edit'));
      if (managingSong &&
          !await ref
              .read(songRepositoryProvider)
              .canManage(session.selectedGroupId!)) {
        return RoutePaths.songs;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: RoutePaths.sessionLoading,
        builder: (_, __) => Consumer(
          builder: (context, ref, _) {
            final resume = ref.watch(sessionResumeProvider);
            return Scaffold(
              backgroundColor: const Color(0xFF101A3A),
              body: Center(
                child: resume.hasError
                    ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Could not restore your last session. Check your connection.',
                      style: TextStyle(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () =>
                          ref.invalidate(sessionResumeProvider),
                      child: const Text(
                        'Retry',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                )
                    : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/images/worship-flow-icon-dark.png',
                      width: 200,
                      height: 200,
                    ),
                    const SizedBox(height: 32),
                    const CircularProgressIndicator(
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      GoRoute(
          path: RoutePaths.profileComplete,
          builder: (_, __) => ProfileCompletionScreen(
              key: ValueKey(ref.read(auth.currentUserProvider)?.id))),
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
        path: RoutePaths.setlistRehearsal,
        builder: (_, state) => RehearsalScreen(
          setlistId: state.pathParameters['setlistId']!,
        ),
      ),
      GoRoute(
          path: RoutePaths.setlistEditor,
          onExit: (_, state) async =>
          await ref
              .read(setlistExitGuardsProvider)[
          state.pathParameters['setlistId']]
              ?.call() ??
              true,
          redirect: (_, __) =>
          ref.read(auth.currentRoleProvider)?.canManageSetlists == true
              ? null
              : RoutePaths.setlists,
          builder: (_, state) => SetlistEditorScreen(
              setlistId: state.pathParameters['setlistId']!)),
      GoRoute(
        path: RoutePaths.songs,
        builder: (_, __) => const SongLibraryScreen(),
        routes: [
          GoRoute(
              path: 'new', builder: (_, __) => const SongEditorScreen.create()),
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