abstract final class RoutePaths {
  static const String login = '/login';
  static const String groups = '/groups';
  static const String groupsMembers = '/groups/:groupId/members';

  static const String setlists = '/setlists';
  static const String setlistDetails = '/setlists/:setlistId';
  static const String setlistEditor = '/setlists/:setlistId/edit';
  static const String setlistRehearsal = '/setlists/:setlistId/rehearse';
  static const String setlistLive = '/setlists/:setlistId/live';

  static const String songs = '/songs';
  static const String songCreate = '/songs/new';
  static const String songDetails = '/songs/:songId';
  static const String songEditor = '/songs/:songId/edit';

  static const String profile = '/profile';
  static const String chartSettings = '/profile/chart-settings';

  // Helpers so callers never string-concat routes.
  static String setlistDetailsFor(String id) => '/setlists/$id';
  static String setlistEditorFor(String id) => '/setlists/$id/edit';
  static String setlistRehearsalFor(String id) => '/setlists/$id/rehearse';
  static String setlistLiveFor(String id) => '/setlists/$id/live';
  static String songDetailsFor(String id) => '/songs/$id';
  static String songEditorFor(String id) => '/songs/$id/edit';
  static String groupMembersFor(String id) => '/groups/$id/members';
}
