# Worship Flow

## Overview

**Every Note for His Glory**. A Flutter worship-team planning UI with mock sign-in, group membership, song browsing, setlist editing, profile display, chart preferences, and setlist rehearsal navigation. This is a UI foundation with in-memory data, not a connected production service.

## Tech stack

`pubspec.yaml`: app version `0.1.0`, unpublished; Dart `>=3.4.0 <4.0.0`, Flutter `>=3.22.0`. Dependencies: Flutter SDK, `firebase_core: ^5.1.0`, `flutter_riverpod: ^2.5.1`, `go_router: ^14.2.0`, `google_fonts: ^6.2.1`, `intl: ^0.19.0`, `uuid: ^4.4.0`. Development: Flutter test SDK and `flutter_lints: ^4.0.0`. These are declared constraints, not resolved versions.

Analyzer fixes were verified with Flutter **3.44.6 / Dart 3.12.2**. Current radio/reorder APIs require a newer Flutter than the declared minimum; the minimum was not changed. Themes use Material widgets and Inter typography through Google Fonts.

## Architecture and implemented scope

- `lib/app/`: binding initialization, `runApp`, and themed `MaterialApp.router`; `main.dart` installs Riverpod `ProviderScope`.
- `lib/core/`: immutable-style models, mock fixtures, routing, colors, typography, and theme state. Shared widget files are whitespace-only placeholders.
- `lib/features/auth/`: mock Google sign-in with loading/error handling and sign-out.
- `groups/`: user-group list, membership display and in-memory role changes. Join/create show stub dialogs; repository methods are no-ops.
- `setlists/`: group lists, upcoming/previous/draft filters, next-service card, details, creation, duplication, deletion, metadata editing, song selection/reordering/removal, arrangement/key selection, draft saving and publishing in memory.
- `songs/`: title/artist search, category filtering, details, arrangement metadata, vocalist keys, and raw primary-arrangement ChordPro source. Editor fields are present; save and creation only display messages.
- `profile/`: read-only account/group display, group switching, sign-out, chart preferences and theme selection. Preferences are in memory; the temporary rehearsal viewer uses font size, scale, line spacing, header size and chart width. Other notation/display preferences await the chart engine.
- `charts/`: shared display-only source adapter/viewer with a collapsible section rail. `rehearsal/`: actual setlist player screen with a song drawer and horizontal song switching. `live/`: whitespace-only placeholder.

## State and data flow

Feature repositories are injected through `authRepositoryProvider`, `groupRepositoryProvider`, and `setlistRepositoryProvider`; all use mock implementations with simulated delays. `AuthRepository` exposes sign-in/out and current-user lookup. `AuthController` owns the feature `sessionProvider`: user, session role, selected group ID, loading and error state. Convenience providers expose user/role/group ID. Sign-out resets session state; startup does not restore a user.

`GroupRepository` exposes all/user-filtered streams, ID lookup, join/create, and member-role updates. Its mock emits snapshots after changes. Derived providers resolve selected group, group by ID, current membership and membership role. `SetlistRepository` exposes a group stream, ID lookup, draft creation/save, metadata updates, publish, duplicate and delete. Stream changes update lists; detail futures are explicitly invalidated by callers. Both mock repositories dispose their broadcast controllers through provider disposal.

Setlist filter state derives sorted lists from the selected group's stream. Upcoming/previous include published setlists; drafts include drafts and published setlists with draft changes. Details and published rehearsal use `publishedItems`; the editor loads `draftItems ?? publishedItems`. Rehearsal previews draft-only items for roles with `canManageSetlists`; other roles see an unpublished-state message. Publishing copies draft items into published items and clears the draft. Metadata updates apply immediately rather than having a separate draft copy.

Song screens read `mockSongs` directly; private search/category providers live in the library screen. Song repository/provider files are placeholders. Theme and chart settings use in-memory `StateNotifierProvider`s; theme defaults to light. Chart settings include typography, scale, spacing, width, Nashville notation and display mode; reset resets chart settings, not theme.

Routing reads the auth layer's `sessionProvider`, matching `RouterRefresh`. Refreshes occur when user ID or selected group ID changes, so sign-in opens group selection, selecting a group opens setlists, clearing the group returns to selection, and sign-out returns to login. The older `SessionController` and router-local provider remain for API compatibility but are not used by redirects.

## Navigation

Initial route is `/login`. Redirect rules as written: unauthenticated requests go to `/login`; authenticated sessions without a group go to `/groups`; authenticated sessions with a group visiting login/groups go to `/setlists`. There are no role-based route guards.

| Route | Destination |
| --- | --- |
| `/login` | Login |
| `/groups` | Group selection |
| `/groups/:groupId/members` | Group members |
| `/setlists` | Setlist list |
| `/setlists/:setlistId` | Published setlist details |
| `/setlists/:setlistId/edit` | Setlist editor |
| `/setlists/:setlistId/rehearse` | Rehearsal: first song, scrollable source chart, song drawer |
| `/setlists/:setlistId/live` | Redirects to that setlist's details |
| `/songs` | Song library |
| `/songs/:songId` | Song details |
| `/songs/:songId/edit` | Song editor stub |
| `/profile` | Profile |
| `/profile/chart-settings` | Chart preferences |

Setlist list cards (including Up Next and drafts) open `/setlists/:setlistId/rehearse` directly, without building Details underneath. The first available item in setlist order is selected. The top bar shows title, performance key, song position, setlist menu, chart settings and Live entry. The drawer shows title/date/status and ordered songs/keys, highlights the selection, and returns to Setlists. Edit and Reorder both open the existing editor for authorized roles; Details & management reuses existing duplicate/publish/delete actions. Returning from management refreshes the setlist, including after deletion. Read-only roles can open Details without management actions.

Horizontal swipes select adjacent songs; each switch resets vertical chart scrolling. Opening/closing the drawer preserves selection and scroll. A separate collapsible section rail jumps to source `{section: ...}` headings (for example Intro, Verse, Chorus, Bridge), independently of the song drawer. Missing setlists support a return to Setlists, load errors support Retry, empty setlists show a message, and missing song/arrangement references show an unavailable-chart message without blocking adjacent songs.

Rehearsal uses the exact referenced arrangement, not the primary arrangement as a fallback. `SourceChartView` and `sourceChartSections` are reusable by future Live Mode; they group source text by section and display original inline chord notation unchanged. No transposition, Nashville conversion or complete ChordPro rendering is implemented. The top-bar key is performance metadata, not a claim that source chords were transposed. Live entry is enabled for permitted roles on nonempty published setlists and retains the existing `/live` redirect to Details. Group selection and switching still rely on session-driven redirects.

## Roles and permissions

| `UserRole` | Manage members | Manage songs/setlists | Enter Live getter |
| --- | --- | --- | --- |
| `administrator` (Administrator) | Yes | Yes | Yes |
| `worshipLeader` (Worship Leader) | No | Yes | Yes |
| `worshipTrainee` (Worship Trainee) | No | No | Yes |

These are `canManageMembers`, `canManageSongs`, `canManageSetlists`, and `canEnterLiveMode` getters. Song/setlist UI uses the session role; member management uses the actual membership role from `roleInGroupProvider`. Mock repositories do not enforce authorization, and editor routes do not enforce these permissions independently. Live remains a redirect regardless of its permission getter.

The group selection screen includes a DEV role-switch FAB and clear-group control. It changes the session role without changing user/membership records. It is described as development-only but is rendered unconditionally, without a debug-build guard. Mock sign-in always returns Jordan as session Administrator, even though group membership roles differ.

## Mock data

- Users: `user-1` Jordan Rivera (Acoustic Guitar), `user-2` Avery Chen (Keys), `user-3` Noah Patel (Drums); example.com emails and initials are fixtures.
- `group-1`, Grace Community Worship / Grace Community Church: Jordan Administrator, Avery Worship Leader, Noah Worship Trainee. `group-2`, Riverside Youth Band / Riverside Chapel: Jordan Worship Leader, Avery Administrator. Join dates are relative to fixture initialization.
- Eight songs, all credited to Worship Flow Originals, with embedded ChordPro and favorite/category metadata:

| ID | Title | Full Band key / BPM |
| --- | --- | --- |
| song-1 | Anchor of the Morning | G / 74 |
| song-2 | Mercy Like a River | D / 68 |
| song-3 | Silent Hallelujah | C / 80 |
| song-4 | Bright Horizon | A / 88 |
| song-5 | Carried Through the Fire | Em / 72 |
| song-6 | Open Hands | B / 76 |
| song-7 | Faithful in the Waiting | F / 66 |
| song-8 | King of Every Season | Ab / 84 |

Every song has a Full Band arrangement; song-1 also has Acoustic (G / 72 BPM). All arrangements use 4/4 and include vocalist-key presets.

| Setlist | Group | Initial state / relative service time | Song IDs in published order |
| --- | --- | --- | --- |
| setlist-1: Sunday Morning Service | group-1 | Published, +7 days 09:30 | 1, 6, 3 |
| setlist-2: Midweek Rehearsal | group-1 | Published with draft changes, +3 days 19:00 | 2, 7; draft adds 4 |
| setlist-3: Youth Night — October | group-1 | Draft, +14 days 18:30 | None; draft has 8, 5 |
| setlist-4: Sunday Morning Service | group-1 | Published, -7 days 09:30 | 2, 7 |
| setlist-5: Friday Youth Service | group-2 | Published, +5 days 19:00 | 4, 6 |

Times are calculated from `DateTime.now()` at fixture initialization, not fixed calendar services. Items reference Full Band arrangements and carry their own performance keys.

## Development roadmap (planned)

The current foundation is the mock-backed UI above. Code comments and UI messages anticipate Firebase authentication/data integration, real group join/create and song writes, account sync/offline persistence, a ChordPro rendering/transposition/Nashville engine, a full rehearsal chart engine and Live functionality. Generated Firebase options and `firebase_core` exist, but bootstrap does not call `Firebase.initializeApp`; backend integration, musical transformations and Live functionality remain unimplemented; the navigation and source-viewing rehearsal foundation is implemented. Phase labels in comments/messages vary and are not a delivery schedule.

## Known limitations

- No durable storage, backend authorization, real Google authentication, notifications, account sync, or offline cache. Publishing only updates memory, despite notification wording in a confirmation dialog.
- Mock group/setlist changes last only for the repository instance; sign-out does not explicitly reset those repositories. Profile updates through the controller affect session state only; profile fields have no editing UI.
- Song creation/save, group join/create, chart transformation and Live functionality remain incomplete. Rehearsal currently displays source text with inline chord symbols rather than a full musical chart renderer; performance key selection changes metadata only.
- Missing setlists have a details fallback, but opening the editor with an unknown ID leaves its loading screen active. Draft-only songs are absent from published details until publishing.
- `test/rehearsal_test.dart` covers direct card navigation, first-song order, drawer/swipe selection, scroll reset, section navigation, draft permissions, editor reuse, management deletion refresh, empty/missing setlists and missing arrangements. No integration tests exist. The declared Flutter lower bound does not guarantee compatibility with current API usage.

## File map

Paths below are relative to `lib/`; every Dart file with non-whitespace content is included. Grouped filenames share the stated directory.

| Directory | Files and purposes |
| --- | --- |
| root | `main.dart`: ProviderScope entry point; `firebase_options.dart`: generated platform configuration (Linux unsupported), unused by bootstrap |
| app/ | `bootstrap.dart`: initialize bindings/runApp; `app.dart`: themed router app |
| core/models/ | `app_user.dart`: profile/copy; `user_role.dart`: roles/permission getters; `session_state.dart`: auth/group/loading/error; `group_member.dart`: member/role/join date; `worship_group.dart`: group/members/accent; `song.dart`: song/arrangements/favorite; `arrangement.dart`: key/tempo/source/presets; `vocalist_key.dart`: singer/key pair; `setlist.dart`: published/draft service model; `setlist_item.dart`: song/arrangement/key reference; `chart_settings.dart`: preferences/display modes |
| core/mock_data/ | `mock_users.dart`: user fixtures/record type; `mock_groups.dart`: groups/membership/user lookup; `mock_songs.dart`: songs/arrangements/ChordPro; `mock_setlists.dart`: relative-date service fixtures |
| core/router/ | `route_paths.dart`: route constants/helpers; `app_router.dart`: routes/redirects/legacy router session; `router_refresh.dart`: auth-session change notifier |
| core/theme/ | `app_colors.dart`: palette; `app_typography.dart`: Inter text styles; `app_theme.dart`: light/dark themes; `theme_providers.dart`: theme controller/provider |
| features/auth/data/ | `auth_repository.dart`: contract/result; `mock_auth_repository.dart`: delayed fixture sign-in/out |
| features/auth/providers/ | `auth_providers.dart`: repository injection, AuthController/session and derived providers |
| features/auth/screens/ | `login_screen.dart`: branding/sign-in/loading/errors |
| features/groups/data/ | `group_repository.dart`: contract; `mock_group_repository.dart`: streams/role mutation/stub join/create |
| features/groups/providers/ | `group_providers.dart`: repository, groups, membership and role providers |
| features/groups/screens/ | `group_selection_screen.dart`: selection/stub join-create/DEV controls; `group_members_screen.dart`: member list/role changes |
| features/setlists/data/ | `setlist_repository.dart`: contract; `mock_setlist_repository.dart`: in-memory stream/CRUD/draft/publish |
| features/setlists/providers/ | `setlist_providers.dart`: repository/detail/list/filter/next-service providers |
| features/setlists/screens/ | `setlists_screen.dart`: list/create/refresh; `setlist_details_screen.dart`: published details/actions; `setlist_editor_screen.dart`: metadata/song ordering/draft/publish/item configuration |
| features/setlists/widgets/ | `setlist_card.dart`: service summary/navigation; `setlist_filter_bar.dart`: filters; `upcoming_service_card.dart`: next-service summary |
| features/songs/screens/ | `song_library_screen.dart`: search/category list; `song_details_screen.dart`: arrangements/raw source; `song_editor_screen.dart`: fields/stub save |
| features/charts/data/ | `source_chart_adapter.dart`: display-only section grouping, preserves source notation |
| features/charts/widgets/ | `source_chart_view.dart`: shared scrollable source preview and collapsible section rail |
| features/rehearsal/screens/ | `rehearsal_screen.dart`: async loading/fallbacks, selected song, toolbar, song drawer and swipe navigation |
| features/profile/screens/ | `profile_screen.dart`: profile/preferences/session actions; `chart_settings_screen.dart`: settings controller/provider and preference controls |

Whitespace-only placeholders excluded from the inventory: `core/widgets/{app_scaffold,empty_state,loading_overlay,primary_button,role_selector_sheet,section_header,status_chip}.dart`, `features/charts/data/chart_transformer.dart`, `features/songs/data/song_repository.dart`, `features/songs/providers/song_providers.dart`, `features/songs/widgets/song_card.dart`, `features/live/screens/live_performance_screen.dart`.
