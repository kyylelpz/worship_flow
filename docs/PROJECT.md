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
- `profile/`: read-only account/group display, group switching, sign-out, chart preferences and theme selection. Preferences are in memory; the shared rehearsal renderer consumes lyric/chord/header font sizes, global scale, line spacing, chart width, display mode and Standard/Nashville notation.
- `charts/`: pure Dart ChordPro parser, typed chart/chord models, transposition and display projections, explicit optional timing grids and a shared Flutter renderer with fixed right-side floating parsed-section bubbles. The old source adapter/viewer remains available for compatibility. `rehearsal/`: actual setlist player screen with a song drawer and horizontal song switching. `live/`: whitespace-only placeholder.

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
| `/setlists/:setlistId/rehearse` | Rehearsal: first song, continuous chord chart, song drawer |
| `/setlists/:setlistId/live` | Redirects to that setlist's details |
| `/songs` | Song library |
| `/songs/:songId` | Song details |
| `/songs/:songId/edit` | Song editor stub |
| `/profile` | Profile |
| `/profile/chart-settings` | Chart preferences |

Setlist list cards (including Up Next and drafts) open `/setlists/:setlistId/rehearse` directly, without building Details underneath. The first available item in setlist order is selected. The top bar shows title, performance key, song position, setlist menu, chart settings and Live entry. The drawer shows title/date/status and ordered songs/keys, highlights the selection, and returns to Setlists. Edit and Reorder both open the existing editor for authorized roles; Details & management reuses existing duplicate/publish/delete actions. Returning from management refreshes the setlist, including after deletion. Read-only roles can open Details without management actions.

Horizontal swipes select adjacent songs; each switch resets vertical chart scrolling. Opening/closing the drawer preserves selection and scroll. Fixed right-side section bubbles use parsed section IDs/labels (including common start/end directives and repeated occurrences), independently of the song drawer. They jump instantly and highlight the section at the top of the viewport as users scroll; at the end of the chart the final section is highlighted. Missing setlists support a return to Setlists, load errors support Retry, empty setlists show a message, and missing song/arrangement references show an unavailable-chart message without blocking adjacent songs.

Rehearsal uses the exact referenced arrangement and `ChartTransformer.prepare` to transpose from source key to the shared item's performance key, then apply a separate personal offset. `ChordChartView` consumes typed display projections and contains no Rehearsal navigation or chord parsing. Compact controls change display mode, personal transpose (+/−12 semitones) and lyric/chord font sizes; notation remains available through Chart Settings. A−, A+ and the adjacent Hide/Show Sections toggle stay pinned to the right while the other toolbar controls scroll horizontally. Personal offsets use an in-memory Riverpod family keyed by arrangement ID; they survive song switching within the app but never change source strings or shared setlist keys. The toolbar shows the effective key; the drawer continues showing shared performance keys. Invalid key requests show an unavailable-chart message; empty charts show a content fallback.

Live entry is enabled for permitted roles on nonempty published setlists and retains the existing `/live` redirect to Details. Group selection and switching still rely on session-driven redirects.

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

## ChordPro engine (Phase 2A)

The engine under `features/charts/{models,data}/` is pure Dart and does not import Flutter or mutate `Song`, `Arrangement`, `SetlistItem`, `ChartSettings`, or canonical ChordPro strings.

- `ChordProParser.parse(source)` produces immutable `ChartDocument`, sections and lines. It retains the exact canonical string, original line text/numbers, repeated metadata values and unsupported directives. Recognized metadata includes title/subtitle, artist/composer/lyricist, key, tempo, time and capo. Common aliases, comments, section/start/end directives, page/column directives and chorus references are classified. Chorus references are retained rather than expanded. Tablature blocks remain opaque.
- Lyrics preserve whitespace. Inline chords have UTF-16 lyric offsets plus original source offsets; adjacent and end-of-line chords retain their anchors. Bare/bracketed/mixed instrumental grids retain original columns, bars, repeat signs and spacing separately from chord tokens. Blank lines remain explicit. Section IDs derive from source line boundaries, stay stable across reparsing identical input and transforms, and distinguish repeated labels; edits before a section can change its ID.
- `ChartTransformer.transpose(chart, semitones: ...)` or `transpose(chart, targetKey: ..., sourceKey: ...)` returns new values with the same anchors/source. Roots and slash bass transpose; quality/extension text is preserved. Supported suffix vocabulary includes minor/major, numbered extensions, sus/add/omit/no, dim/aug/alt, plus/minus, degree/half-diminished and parenthesized alterations. Unknown tokens stay literal. Target spelling favors the selected scale's letter names; offset-only transposition selects conventional signatures. Identity transforms preserve original chord spellings. Major-to-minor conversion is rejected because it would require reharmonization.
- `ChartTransformer.display(chart, settings, key: ...)` projects Lyrics + Chords, Chords Only or Lyrics Only and Standard/Nashville notation without reparsing or moving anchors. Hidden content becomes absent in projection fields; canonical lines/directives and section structure remain accessible. Grid layout is separate from lyric text.
- Nashville uses tonic-relative major or **natural-minor** degrees: in A minor, Am = `1m`, C = `3`, F = `6`, G# = `#7`. Qualities/extensions remain literal (G7/B in C = `57/7`); slash bass is also numbered. Accidentals follow the note's spelled scale degree. This is not the alternate relative-major minor-numbering convention.
- `ChartTransformer.prepare(song: ..., arrangement: ..., item: ..., settings: ...)` validates matching references, parses the existing arrangement, transposes to the item's performance key and projects settings. Source-key precedence is valid source `{key}`, arrangement performance key, then song default. It accepts optional `personalSemitones`, uses arrangement time signature as a grid fallback, and now feeds Rehearsal's shared `ChordChartView`. The old `SourceChartView` API is retained but no longer used by Rehearsal.

Limitations: not a complete ChordPro specification implementation. Standalone directives are recognized; inline/malformed directives remain literal. Unknown chord text, unsupported directives and tablature are preserved, not interpreted. There is no tablature transposition, fretboard/capo realization, automatic chorus expansion, polychord/microtonal analysis, general ChordPro rhythmic-grid interpretation beyond the explicit Worship Flow extension below, key-modulation-aware transformations, or harmonic/melodic-minor inference. Bare lines consisting entirely of supported chord/layout tokens are treated as chord-only lines (so a lone `A` is ambiguous). Offsets count UTF-16 code units, not rendered pixels/graphemes; the renderer measures anchors and stacks colliding labels without changing offsets. Target-key transposition needs a known source key; Nashville needs a key; invalid explicit keys or mismatched references raise `ArgumentError`. Source metadata remains canonical while `ChartDocument.key` records the effective transformed key.

## Chart renderer and timing grids (Phase 2B)

`ChordChartView` renders a continuous vertical scroll, never pages. Lyrics + Chords measures each rendered lyric segment and chord label with Flutter text metrics. When distinct anchors would collide, the layout inserts only the measured horizontal deficit plus 4 pixels of label clearance, moving the following lyric segment and all subsequent anchors together. This is display geometry only: canonical source, lyric strings and UTF-16 anchor offsets are unchanged. Expanded lines stay on one chord row when they fit; words wrap first, then oversized words split at chord anchors and grapheme boundaries. Chords sharing the exact same lyric offset retain a last-resort vertical lane because both must remain anchored to the same character. There is no longer a separate chord-width gutter; the narrow section-button overlay gutter remains independent. Lyrics Only retains text/sections and hides chords. Chords Only renders explicit valid timing grids where available, otherwise ordered chord sequences labelled **no timing**. Blank lyric lines and repeated parsed sections are retained. Font sizes, global scale and system text scaling apply; a chord symbol wider than the entire available line may wrap within its label. Layout is remeasured on font/style, system scale, transformation or viewport changes. The renderer supports left-to-right chart layout; complex bidirectional layout, printing and pagination are not implemented.

### Floating section navigation (Phase 2B.2)

The old left rail is removed from `ChordChartView`. Rounded section buttons form a fixed overlay at the upper-right of the chart viewport, below the pinned font controls. Short labels include IN, V1, CH, BR and OUT. Repeated abbreviations receive occurrence numbers (for example CH1/CH2 or V1·1/V1·2); full-label tooltips and accessibility descriptions include their ordered section position. Parsed IDs and existing `Scrollable.ensureVisible` anchors are retained; jumps have zero animation duration.

The active bubble follows chart scrolling and recomputes after viewport, text-scale or chart-setting changes. The last section becomes active at the chart bottom. The bubble stack has 48-pixel minimum touch targets, uses the current theme, respects side/bottom safe areas, and is bounded to 360 pixels or the available viewport height. Longer lists scroll independently of the chart. A narrow right gutter reserves overlay space even while hidden, so Hide/Show affects only the bubbles: lyrics do not rewrap and chart scroll, song selection, personal transpose and preferences remain unchanged. The visibility choice persists during song switching within the current Rehearsal screen. Horizontal song swipes and the setlist drawer retain their existing behavior. Buttons are not draggable. No Performance Mode or translucent settings overlay is implemented.

Optional timing grids live in the **same canonical arrangement source**, alongside lyric sections. Supported Worship Flow syntax:

```chordpro
{key: D}
{time: 4/4}
{section: Verse 1}
[D]First phrase [G]second phrase
[Bm]Third phrase [A]fourth phrase

{grid_subdivision: 1}
{start_of_grid: Verse 1}
| D - - - | G - - - |
| Bm - - - | A - - - |
{end_of_grid}
```

- `TimingGrid`, `TimingMeasure` and `TimingSlot` represent measures, explicit equal-duration slots, chord-change events and sustains. A chord starts a new event; `-` sustains the previous event, including across measures/rows. A leading sustain without a preceding chord warns and invalidates timing. No durations are inferred from lyric anchors.
- `{time: 3/4}`, `{time: 4/4}` and `{time: 6/8}` are supported. `{grid_subdivision: N}` allows integers 1–8 subdivisions **per denominator-note beat**, default 1. Thus 4/4 with subdivision 2 needs eight slots per measure, 3/4 needs six, and 6/8 needs twelve. 6/8 at subdivision 1 explicitly means six eighth-note slots, not two inferred dotted-quarter beats. Parsed documents default to 4/4 when no meter is supplied; `prepare` uses the arrangement time signature as fallback. Directives apply in source order; changes within one grid are flagged unsupported.
- Multiple changes are supported, for example `| D - G - |` in 4/4. Bare and bracketed chord names work. Enclosing bars are required. Bar/repeat markers such as `|:`, `||` and `:|`, repeated measures, original rows and canonical source are retained; repeat playback/expansion and `%` measure-repeat shorthand are not implemented.
- A labelled grid associates with the nearest preceding lyric section of the same normalized label, or the first following match. Repeated labels retain distinct IDs; an unmatched grid is a standalone instrumental section. In Chords Only, associated valid grids appear under their lyric section; the separate grid section is not duplicated in section navigation. Other modes retain lyric content, with standalone instrumental chord passages where applicable.
- Lyric and grid chord-change sequences are compared using pitch, quality and bass, coalescing consecutive identical events. Differences produce visible warnings; neither source representation is rewritten. Chords Only chooses the explicit valid grid; lyric modes retain lyric anchors. Invalid counts, meter/subdivision, tokens, missing bars and orphan sustains warn and fall back to untimed sequences where parsable. These checks are conservative, not automatic musical synchronization.
- Grid chords transpose and convert to Nashville through the same engine operations as lyric chords. Valid grid slot duration is available in whole-note units. Measure cells have responsive equal widths and indexed subdivisions; wrapping changes screen layout only, not event timing.

There is no playback clock, metronome, tempo automation, tuplets, variable-duration slot syntax, nested sections/repeats, polyrhythm, inferred rhythmic alignment or Live implementation. Unknown/malformed source remains canonical; unsupported timing is reported instead of fabricated.

## Development roadmap (planned)

The current foundation is the mock-backed UI above. Code comments and UI messages anticipate Firebase authentication/data integration, real group join/create and song writes, account sync/offline persistence, advanced notation/playback features and Live functionality. The Phase 2A engine and Phase 2B shared renderer/explicit grid foundation are implemented above. Generated Firebase options and `firebase_core` exist, but bootstrap does not call `Firebase.initializeApp`; backend integration and Live functionality remain unimplemented; Rehearsal navigation and chart rendering are implemented. Phase labels in comments/messages vary and are not a delivery schedule.

## Known limitations

- No durable storage, backend authorization, real Google authentication, notifications, account sync, or offline cache. Publishing only updates memory, despite notification wording in a confirmation dialog.
- Mock group/setlist changes last only for the repository instance; sign-out does not explicitly reset those repositories. Profile updates through the controller affect session state only; profile fields have no editing UI.
- Song creation/save, group join/create, advanced notation/playback and Live functionality remain incomplete. Timing support is limited to the explicit grid syntax above; untimed lyric chords never acquire inferred durations. Chart preferences and personal offsets remain in memory.
- Missing setlists have a details fallback, but opening the editor with an unknown ID leaves its loading screen active. Draft-only songs are absent from published details until publishing.
- `test/anchored_lyric_line_test.dart` covers minimal spacing, adjacent/mid-word/slash chords, word/grapheme wrapping, typography/width changes, transposition and unchanged canonical anchors. `test/floating_sections_test.dart` covers immediate jumps, repeated occurrence identity, scroll highlighting, fixed overlay positioning, state-preserving visibility, safe areas and independent scrolling on narrow/scaled and landscape-sized layouts. `test/chord_chart_view_test.dart` covers anchor alignment/collision lanes, wrapping, narrow/scaled layouts, three modes, transformations, timing rendering, repeated-section navigation and personal controls. `test/timing_grid_test.dart` covers meters/subdivisions, association, changes/sustains, markers, mismatches, validation and grid transformations. `test/chordpro_engine_test.dart` covers parsing, exact anchors, metadata/directives, grids, malformed input, transposition/spelling, Nashville, display modes and every mock arrangement/setlist item. `test/rehearsal_test.dart` covers direct card navigation, first-song order, drawer/swipe selection, scroll reset, section navigation, draft permissions, editor reuse, management deletion refresh, empty/missing setlists and missing arrangements. No integration tests exist. The declared Flutter lower bound does not guarantee compatibility with current API usage.

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
| features/charts/models/ | `chart_document.dart`: immutable chart/anchor/directive and display projection types; `chord_symbol.dart`: note/key/chord parsing, spelling and degree conversion |
| features/charts/data/ | `chordpro_parser.dart`: source parsing; `timing_grid_parser.dart`: optional explicit-grid attachment/validation; `chart_transformer.dart`: transposition/display/preparation API; `source_chart_adapter.dart`: existing display-only section grouping |
| features/charts/widgets/ | `chord_chart_view.dart`: shared continuous renderer, measures and floating parsed-section navigation; `anchored_lyric_line.dart`: measured horizontal lyric expansion, safe wrapping and coincident-anchor fallback lanes; `source_chart_view.dart`: retained legacy preview |
| features/charts/providers/ | `chart_providers.dart`: personal arrangement transpose offsets |
| features/rehearsal/screens/ | `rehearsal_screen.dart`: async loading/fallbacks, selected song, toolbar, song drawer and swipe navigation |
| features/profile/screens/ | `profile_screen.dart`: profile/preferences/session actions; `chart_settings_screen.dart`: settings controller/provider and preference controls |

Whitespace-only placeholders excluded from the inventory: `core/widgets/{app_scaffold,empty_state,loading_overlay,primary_button,role_selector_sheet,section_header,status_chip}.dart`, `features/songs/data/song_repository.dart`, `features/songs/providers/song_providers.dart`, `features/songs/widgets/song_card.dart`, `features/live/screens/live_performance_screen.dart`.
