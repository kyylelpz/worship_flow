# Worship Flow

## Overview

**Every Note for His Glory**. A Flutter worship-team planning UI with mock sign-in, group membership, group-scoped song/arrangement management, setlist editing, profile display, chart preferences, and setlist rehearsal navigation. This is a UI foundation with in-memory data, not a connected production service.

## Tech stack

`pubspec.yaml`: app version `0.1.0`, unpublished; Dart `>=3.4.0 <4.0.0`, Flutter `>=3.22.0`. Dependencies: Flutter SDK, `firebase_core: ^5.1.0`, `flutter_riverpod: ^2.5.1`, `go_router: ^14.2.0`, `google_fonts: ^6.2.1`, `intl: ^0.19.0`, `uuid: ^4.4.0`. Development: Flutter test SDK and `flutter_lints: ^4.0.0`. These are declared constraints, not resolved versions.

Analyzer fixes were verified with Flutter **3.44.6 / Dart 3.12.2**. Current radio/reorder APIs require a newer Flutter than the declared minimum; the minimum was not changed. Themes use Material widgets and Inter typography through Google Fonts.

## Architecture and implemented scope

- `lib/app/`: binding initialization, `runApp`, and themed `MaterialApp.router`; `main.dart` installs Riverpod `ProviderScope`.
- `lib/core/`: immutable-style models, mock fixtures, routing, colors, typography, and theme state. Shared widget files are whitespace-only placeholders.
- `lib/features/auth/`: mock Google sign-in with loading/error handling and sign-out.
- `groups/`: user-group list, membership display and in-memory role changes. Join/create show stub dialogs; repository methods are no-ops.
- `setlists/`: group lists, upcoming/previous/draft filters, next-service card, details, creation, duplication, deletion, metadata editing, song selection/reordering/removal, arrangement/key selection, draft saving and publishing in memory.
- `songs/`: reactive group-scoped CRUD, search/category filters and read-only details with no actions (favorite toggle removed). Songs own title, artist, category, favorite and shared Vocal Key Presets. Arrangements own name, BPM, meter, optional reference URL and canonical source; the source is read-only in the arrangement form and edited through the full-screen highlighted ChordPro editor. Referenced deletion is blocked.
- `profile/`: read-only account/group display, group switching, sign-out, chart preferences and theme selection. Preferences are in memory; the shared rehearsal renderer consumes lyric/chord/header font sizes, global scale, line spacing, chart width, display mode and Standard/Nashville notation.
- `charts/`: pure Dart ChordPro parser, typed chart/chord models, transposition and display projections, explicit optional timing grids and a shared Flutter renderer with fixed right-side floating parsed-section bubbles. The old source adapter/viewer remains available for compatibility. `rehearsal/`: actual setlist player screen with a song drawer and horizontal song switching.

## State and data flow

Feature repositories are injected through `authRepositoryProvider`, `groupRepositoryProvider`, `setlistRepositoryProvider`, and `songRepositoryProvider`; all use mock implementations with simulated delays. `AuthRepository` exposes sign-in/out and current-user lookup. `AuthController` owns the feature `sessionProvider`: user, session role, selected group ID, loading and error state. Convenience providers expose user/role/group ID. Sign-out resets session state; startup does not restore a user.

`GroupRepository` exposes all/user-filtered streams, ID lookup, join/create, and member-role updates. Its mock emits snapshots after changes. Derived providers resolve selected group, group by ID, current membership and membership role. `SetlistRepository` exposes a group stream, ID lookup, draft creation/save, metadata updates, publish, duplicate and delete. Stream changes update lists; detail futures are explicitly invalidated by callers. Both mock repositories dispose their broadcast controllers through provider disposal.

Setlist filter state derives sorted lists from the selected group's stream. Upcoming/previous include published setlists; drafts include drafts and published setlists with draft changes. Published rehearsal uses `publishedItems`; the editor loads `draftItems ?? publishedItems`. Rehearsal previews draft-only items for roles with `canManageSetlists`; other roles see an unpublished-state message. Publishing copies draft items into published items and clears the draft. Metadata updates apply immediately rather than having a separate draft copy.

`songRepositoryProvider` injects `MockSongRepository`, backed by `songCatalogProvider` / `InMemorySongCatalog`. `groupSongsProvider` subscribes to the selected group's authorized catalog and restarts on session/membership changes; `songsListProvider` and `songByIdProvider` derive reactive lookups. Library, details, editor, setlist selection/details and Rehearsal now use these providers. Only catalog seeding reads `mockSongs`. Search/category state remains in the library screen; unavailable categories fall back to All after group/catalog changes. Theme and chart settings use in-memory `StateNotifierProvider`s; theme defaults to light. Chart settings include typography, scale, spacing, width, Nashville notation and display mode; reset resets chart settings, not theme.

Routing reads the auth layer's `sessionProvider`, matching `RouterRefresh`. Refreshes occur when user ID or selected group ID changes, so sign-in opens group selection, selecting a group opens setlists, clearing the group returns to selection, and sign-out returns to login. The older `SessionController` and router-local provider remain for API compatibility but are not used by redirects.

## Navigation

Initial route is `/login`. Redirect rules as written: unauthenticated requests go to `/login`; authenticated sessions without a group go to `/groups`; authenticated sessions with a group visiting login/groups go to `/setlists`. Song creation/editing routes check repository-authorized group management access; other existing routes retain their prior guards.

| Route | Destination |
| --- | --- |
| `/login` | Login |
| `/groups` | Group selection |
| `/groups/:groupId/members` | Group members |
| `/setlists` | Setlist list |
| `/setlists/:setlistId/edit` | Setlist editor |
| `/setlists/:setlistId/rehearse` | Rehearsal: first song, continuous chord chart, song drawer |
| `/songs` | Selected-group song library |
| `/songs/new` | Create song with initial arrangements (authorized managers only) |
| `/songs/:songId` | Song details |
| `/songs/:songId/edit` | Song metadata and arrangement management (authorized managers only) |
| `/profile` | Profile |
| `/profile/chart-settings` | Chart preferences |

Setlist cards open `/setlists/:setlistId/rehearse` directly and select the first item. Rehearsal is the sole chart-viewing mode. The header shows Song title/artist, item Performance Key and exact Arrangement meter; a personal offset adds a separate displayed-key label. For song managers the header opens an information popup with current arrangement, stored worship leader/key and authorized Edit Song/Edit Setlist actions; other users see ordinary text. The drawer retains title/date/status, ordered songs/keys and highlighting, Back to Setlists and a single authorized Edit Setlist action. The redundant Setlist Details destination was removed. Publishing, duplication and confirmed deletion are available in the editor. Returning from editing refreshes metadata without replacing unsaved parent state.

Horizontal swipes select adjacent songs; each switch resets vertical chart scrolling. Opening/closing the drawer preserves selection and scroll. Fixed right-side section bubbles use parsed section IDs/labels (including common start/end directives and repeated occurrences), independently of the song drawer. They jump instantly and highlight the section at the top of the viewport as users scroll; at the end of the chart the final section is highlighted. Missing setlists support a return to Setlists, load errors support Retry, empty setlists show a message, and missing song/arrangement references show an unavailable-chart message without blocking adjacent songs.

Rehearsal uses the exact referenced arrangement and `ChartTransformer.prepare`: numbered source resolves directly in the shared item key, known-source letter chords transpose to it, then the separate personal offset applies once. `ChordChartView` remains navigation-independent. Display mode, personal transpose (+/−12), typography, notation and pinned floating-section controls retain existing behavior. Personal offsets are in-memory Riverpod state keyed by arrangement ID; they never modify canonical strings or shared setlist keys. Invalid key requests show an unavailable-chart message; empty charts show a content fallback.


## Roles and permissions

| `UserRole` | Manage members | Manage songs/setlists |
| --- | --- | --- |
| `administrator` (Administrator) | Yes | Yes |
| `worshipLeader` (Worship Leader) | No | Yes |
| `worshipTrainee` (Worship Trainee) | No | No |

These are `canManageMembers`, `canManageSongs` and `canManageSetlists` getters. Setlist UI retains session-role checks; member management uses the actual membership role from `roleInGroupProvider`. Song management requires both an Administrator/Worship Leader session role and an Administrator/Worship Leader membership in the selected group. Song reads also verify authenticated membership and selected-group scope. `canManageSongsProvider`, protected `/songs/new` and song-edit routes, and every `SongRepository` mutation enforce these checks; repository operations recheck the current session after asynchronous membership lookup. Route refresh observes session roles and membership changes. Existing group/setlist mock repositories retain their previous permission behavior; song catalog integrity checks are separate from backend authorization. Setlist editor routes and UI require setlist-management permission.

The group selection screen includes a DEV role-switch FAB and clear-group control. It changes the session role without changing user/membership records. For songs it can reduce access, but cannot elevate a trainee membership into a manager. It is described as development-only but is rendered unconditionally, without a debug-build guard. Mock sign-in always returns Jordan as session Administrator, even though group membership roles differ.

## Mock data

- Users: `user-1` Jordan Rivera (Acoustic Guitar), `user-2` Avery Chen (Keys), `user-3` Noah Patel (Drums); example.com emails and initials are fixtures.
- `group-1`, Grace Community Worship / Grace Community Church: Jordan Administrator, Avery Worship Leader, Noah Worship Trainee. `group-2`, Riverside Youth Band / Riverside Chapel: Jordan Worship Leader, Avery Administrator. Join dates are relative to fixture initialization.
- Each of the two fixture groups starts with an independent copy of the same eight songs/arrangement IDs, preserving existing setlist references. Ownership is stored by group in the catalog rather than adding fields to the public models; new IDs use UUIDs and changes do not propagate between groups. All seed songs are credited to Worship Flow Originals, with embedded ChordPro and favorite/category metadata:

| ID | Title | Source key / Full Band BPM |
| --- | --- | --- |
| song-1 | Anchor of the Morning | G / 74 |
| song-2 | Mercy Like a River | D / 68 |
| song-3 | Silent Hallelujah | C / 80 |
| song-4 | Bright Horizon | A / 88 |
| song-5 | Carried Through the Fire | Em / 72 |
| song-6 | Open Hands | B / 76 |
| song-7 | Faithful in the Waiting | F / 66 |
| song-8 | King of Every Season | Ab / 84 |

Every song has a Full Band arrangement; song-1 also has Acoustic (72 BPM). All fixture arrangements use 4/4. Fixture arrangement presets were merged/deduplicated into song-level lists (song-1: Jordan G, Avery A); there were no conflicting fixture keys. Existing song/arrangement IDs, source strings and setlist performance keys were retained. Existing items have no selected vocalist until explicitly chosen; no leader was guessed.

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
- Canonical source may mix letters and Nashville roots `1`–`7`, prefixed accidentals, supported qualities/extensions and numbered slash bass (`[5m7]`, `[b7/1]`, `[1/3]`). `ChordProParser.parse(numberKey: ...)` supplies an explicit numbered context; otherwise the first source `{key}`/`{k}` remains supported. In Rehearsal the item key overrides source metadata for numbers. Keyless numbered source and optional grids render without a missing-source-key warning. Unsupported numeric tokens remain literal with warnings. Original degree spellings, source text and anchors survive transforms. Roman numerals, mixed letter/number slash roots, fractional extensions and arbitrary numeric suffixes remain unsupported.
- `ChartTransformer.prepare` validates references and selects the item key, explicit `previewKey`, or first available song Vocal Key Preset. Without any selected key it requests one instead of guessing. Numbers resolve directly in that context; letter chords use explicit `sourceKey` or source `{key}` for transposition. Unknown-source letters stay literal with an actionable warning; a known letter-source major/minor change is rejected. Personal offsets apply afterward once. Arrangement meter is the grid fallback. No title/artist/key/tempo/time directive is required for a numbered arrangement; header metadata comes from the Song/Arrangement/item. The retained `SourceChartView` is no longer used by Rehearsal.

Limitations: not a complete ChordPro specification implementation. Standalone directives are recognized; inline/malformed directives remain literal. Unknown chord text, unsupported directives and tablature are preserved, not interpreted. There is no tablature transposition, fretboard/capo realization, automatic chorus expansion, polychord/microtonal analysis, general ChordPro rhythmic-grid interpretation beyond the explicit Worship Flow extension below, key-modulation-aware transformations, or harmonic/melodic-minor inference. Bare lines consisting entirely of supported chord/layout tokens are treated as chord-only lines (so a lone `A` is ambiguous). Offsets count UTF-16 code units, not rendered pixels/graphemes; the renderer measures anchors and stacks colliding labels without changing offsets. Target-key transposition needs a known source key; Nashville needs a key; invalid explicit keys or mismatched references raise `ArgumentError`. Source metadata remains canonical while `ChartDocument.key` records the effective transformed key.

## Chart renderer and timing grids (Phase 2B)

`ChordChartView` renders a continuous vertical scroll, never pages. Lyrics + Chords measures each rendered lyric segment and chord label with Flutter text metrics. When distinct chord anchors would collide, the layout inserts the measured horizontal deficit plus a font-size-aware minimum clearance of max(8dp, effectiveChordFontSize × 0.5), preserving chord-to-lyric alignment. This is display geometry only: canonical source, lyric strings and UTF-16 anchor offsets are unchanged. Expanded lines stay on one chord row when they fit; words wrap first, then oversized words split at chord anchors and grapheme boundaries. Chords sharing the exact same lyric offset retain a last-resort vertical lane because both must remain anchored to the same character. There is no longer a separate chord-width gutter; the narrow section-button overlay gutter remains independent. Lyrics Only retains text/sections and hides chords. Chords Only renders explicit valid timing grids where available, otherwise ordered chord sequences labelled **no timing**. Blank lyric lines and repeated parsed sections are retained. Font sizes, global scale and system text scaling apply; a chord symbol wider than the entire available line may wrap within its label. Layout is remeasured on font/style, system scale, transformation or viewport changes. The renderer supports left-to-right chart layout; complex bidirectional layout, printing and pagination are not implemented.

### Floating section navigation (Phase 2B.2)

The old left rail is removed from `ChordChartView`. Rounded section buttons form a fixed overlay at the upper-right of the chart viewport, below the pinned font controls. Short labels include IN, V1, CH, BR and OUT. Repeated abbreviations receive occurrence numbers (for example CH1/CH2 or V1·1/V1·2); full-label tooltips and accessibility descriptions include their ordered section position. Parsed IDs and existing `Scrollable.ensureVisible` anchors are retained; jumps have zero animation duration.

The active bubble follows chart scrolling and recomputes after viewport, text-scale or chart-setting changes. The last section becomes active at the chart bottom. The bubble stack has 48-pixel minimum touch targets, uses the current theme, respects side/bottom safe areas, and is bounded to 360 pixels or the available viewport height. Longer lists scroll independently of the chart. A narrow right gutter reserves overlay space even while hidden, so Hide/Show affects only the bubbles: lyrics do not rewrap and chart scroll, song selection, personal transpose and preferences remain unchanged. The visibility choice persists during song switching within the current Rehearsal screen. Horizontal song swipes and the setlist drawer retain their existing behavior. Buttons are not draggable. The translucent settings overlay is not implemented.

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

There is no playback clock, metronome, tempo automation, tuplets, variable-duration slot syntax, nested sections/repeats, polyrhythm, inferred rhythmic alignment. Unknown/malformed source remains canonical; unsupported timing is reported instead of fabricated.

## Song library CRUD (Phase 3A)

- `SongRepository` provides authorized catalog streams/lookups, song create/update/delete and arrangement create/update/duplicate/delete. `Song.copyWith` and `Arrangement.copyWith` support immutable edits while preserving IDs. Song metadata saves cannot replace the arrangement collection; arrangement operations have their own methods. Repository snapshots freeze arrangement/preset lists.
- Creating a song requires at least one valid arrangement. Existing song metadata is saved with **Save Song**; arrangement actions on existing songs save immediately, as stated in the editor. New-song arrangements remain local drafts until the song is created. Opening Add Song pushes onto the library history; successful creation pops Add Song back to the existing Song Library to retain its Setlists history, falling back to the library route only when no previous page exists. Song Library always exposes Back and falls back to Setlists for direct access, including Android Back. Add/Edit Song exposes an explicit Back button and shares discard confirmation with Android Back for unsaved metadata or new-song arrangement drafts. With no previous page, Back falls back to Song Library. Group changes block an already-open metadata editor from saving into another group's catalog.
- Song validation requires title, artist and category; the editor offers Praise, Worship, Communion or Other with required custom input. Vocal Key Presets are song-level, with required names/major-or-minor keys and case-insensitive unique names. Arrangements require name, source, integer BPM 1–400 and meter 3/4, 4/4 or 6/8; an optional reference link must be http(s) with a host. Song default key and Arrangement performance key were removed. Source is never automatically trimmed, transposed or rewritten; full source linting remains deferred.
- Song/arrangement deletion requires confirmation. `SetlistSongReferences` supplies an immediate in-memory lookup across both published and draft items in the same group. Referenced records cannot be deleted; a song must keep one arrangement. A referenced letter-source arrangement cannot switch its known source major/minor mode; duplicate it instead. Edits retain IDs and existing setlist performance keys remain unchanged.
- The production mock setlist provider wires the shared catalog's synchronous `validateReferences` into draft saves. A song/arrangement deleted after selection in an unsaved editor causes a clear save error; Publish stops after a failed save. Removing references in the normal setlist editor permits later deletion. A repository without reference-check capability fails closed for destructive song operations.
- `ArrangementEditorScreen` edits name/BPM/meter/reference URL and shows read-only canonical source with Edit navigation. `openChordProEditor` returns draft text; only Save Arrangement (or creating the new Song) persists it. Vocal presets are edited/saved with Song metadata. The general Song Editor is reused from setlist configuration and the Rehearsal popup; saving pops to its existing caller. Song Details lists metadata, arrangements and shared presets without raw source or arrangement mutation menus.
- Success/error snackbars and form validation provide feedback; newer arrangement-operation feedback replaces earlier snackbars. Data remains in memory for the provider/container lifetime, without account sync or durable storage. The mock membership/session checks are application safeguards, not a deployed backend security system.

### Setlist configuration and key ownership

Newly added items require explicit selection of a song Vocal Key Preset; no arbitrary key is assigned. Configuration keeps arrangement selection independent of the key and displays `Vocalist · Key` choices. Songs without presets offer Edit Song to add one; Done requires an available arrangement and a key. Existing stored keys remain usable even if their preset changes/disappears. Editing a Song in the configuration sheet refreshes metadata/presets without losing the unsaved setlist name, order or item selection. Reference validation rejects missing songs/arrangements and invalid or unset item keys before saving. Data remains in-memory; no persisted database migration was required.

`test/song_refactor_test.dart` covers keyless source/grids, effective-key precedence, personal offsets, explicit preview context, unknown-source letters, merged fixture ownership, category/reference editing, nested save returns, read-only Song Details (no favorite action) and header-popup state. Existing repository, navigation and Rehearsal tests were migrated to the new ownership and sole-mode navigation.

## Advanced ChordPro editor (Phase 3B)

- `openChordProEditor(context, source)` still returns `Future<String?>`: Save returns the exact source draft, while cancellation returns null. Optional named `vocalistKeys`, `previewKey` and `timeSignature` provide preview context without changing existing callers. The Arrangement Editor passes its current meter and Song-level presets (including unsaved Song-form preset drafts). `ChordProEditorScreen` replaces the basic UI; its legacy filename and `BasicChordProEditorScreen` type alias retain compatibility.
- The monospaced, vertically scrollable source field preserves whitespace, line endings, selection and canonical text. Complete directives/section tags are green, recognized metadata values magenta, supported bracketed letter/Nashville chords teal, and lyrics/other text inherit the theme color. Bare/mixed chord-only instrumental rows also highlight chords. Colors adapt to light/dark themes; active IME composition retains underlining. Highlighting uses the engine chord vocabulary and caches lexical runs per unchanged line; it does not parse a chart on each keystroke.
- Back, Undo, Redo, Preview/Edit source and Save are accessible toolbar actions. Typing, deletion, paste and shortcut edits share selection-aware history; hardware undo/redo intents use the same controller. The editor history retains at most 100 snapshots, pruning beyond approximately two million source code units while retaining one undo step. Redo clears after a new edit. The horizontal shortcut strip stays above the keyboard and provides chord brackets, section/verse/chorus pairs, key, tempo, time, grid markers, bars and sustains. Paired shortcuts wrap a selection (or put the caret inside an empty pair); fixed markers replace the selection. No surrounding text or line breaks are automatically rewritten.
- Preview calls the existing parser through `ChartTransformer.prepare`, then displays `ChordChartView` with current chart settings. It uses an explicit preview key or the first valid supplied Song Vocal Key Preset; otherwise it asks the user for a key. Source `{key}` is not required for numbered source. Standard/Nashville can be switched locally without changing global preferences. Source/key changes trigger preparation when preview is opened/applied; preference-only changes reproject the cached document. Engine warnings stay visible, and invalid preview requests do not prevent source editing or draft saving. Letter chords retain the existing known-source-key safeguards.
- Source selection and source/chart scroll positions survive editor/preview switching. Save only returns a draft: Save Arrangement, or Save Song for a new song, remains the persistence boundary. Toolbar/Android Back confirm unsaved source changes; unchanged or fully undone text leaves without confirmation. Empty source cannot be returned as a valid arrangement draft. Existing song-management permissions and the group captured when the editor opened gate editing/history/shortcuts/Save; read-only preview remains available. Song Details remains read-only with no favorite actions.

Limitations: lexical highlighting is not a full ChordPro linter or formatter; malformed/unsupported notation is preserved, with only existing engine diagnostics in Preview. Text layout and line-cache traversal still scale with document size; there is no virtualized code editor, multi-cursor editing, code completion, folding or background isolate parsing. History and preview keys are route-local and not persisted. Import/export and backend storage are not implemented. `test/chordpro_editor_test.dart` covers syntax/composition, cursor and shortcut edits, bounded history, keyboard undo, keyless preview/warnings, chart preferences/scroll restoration, exact save/cancel, discard confirmation, parent draft persistence, permissions and narrow scaled keyboard/theme layouts.

## Superscript chord display

`ChordLabel` is shared by lyric anchors, untimed instrumental chord sequences, invalid-grid fallback sequences and explicit timing-grid chord events. It displays extension numbers **7, 9, 11 and 13** at 65% of the chord font size with their baseline raised by 35% of the scaled chord font size. Roots (letter or Nashville degree), minor markers, accidentals, slash bass and other suffix text remain on the normal baseline. For example `Bm7/F#` retains normal `Bm` and `/F#` around a raised `7`; `A7sus4` raises `7` and retains literal `sus4`. Major/add/sus/dim/aug/altered text is preserved, not replaced with new symbols.

Rendering and horizontal collision measurements share the same shaped-run layout, including raised ascent/descent, global font settings, accessibility scaling and wrapped labels. Typography does not move canonical lyric anchors or change source strings or harmonic semantics. Unknown/malformed labels remain plain. Numeric source conversion is implemented in the engine, independently of typography. Extremely long labels may wrap at run/grapheme boundaries; full bidirectional music typography remains unsupported.

Ordinary inline chord-only passages such as `[1] - - - |: [5/1]  - - - :| %` retain markers, repeats, inter-token whitespace and source line breaks in both chord-visible modes. The renderer places shared styled chord labels alongside literal layout text and wraps on narrow viewports without inferring durations or expanding repeats. Lyric hyphens remain lyrics. In Chords Only, lyric-attached chords still use the untimed extracted sequence fallback; explicit timing grids retain their existing precedence. `test/nashville_source_test.dart` covers mixed-source conversion, source-key warnings, major/minor and slash resolution, two-stage transposition, canonical anchors, explicit grids and scaled instrumental rendering across all modes.

## Development roadmap (planned)

The current foundation is the mock-backed UI above. Code comments and UI messages anticipate Firebase authentication/data integration, real group join/create and persistent song writes, account sync/offline persistence, advanced notation/playback features. The Phase 2A engine, Phase 2B renderer/explicit grids, Phase 3A in-memory song CRUD and Phase 3B source editor are implemented above. Generated Firebase options and `firebase_core` exist, but bootstrap does not call `Firebase.initializeApp`; backend integration remains unimplemented; Rehearsal navigation and chart rendering are implemented. Phase labels in comments/messages vary and are not a delivery schedule.

## Known limitations

- No durable storage, backend authorization, real Google authentication, notifications, account sync, or offline cache. Publishing only updates memory.
- Mock group/setlist changes last only for the repository instance; sign-out does not explicitly reset those repositories. Profile updates through the controller affect session state only; profile fields have no editing UI.
- Group join/create, persistent backend integration, advanced musical notation/playback remain incomplete. Timing support is limited to the explicit grid syntax above; untimed lyric chords never acquire inferred durations. Chart preferences and personal offsets remain in memory.
- Missing setlists display unavailable states. Draft-only songs remain absent from published Rehearsal. Editing a preset does not silently update already-stored setlist keys or vocalist names; configuration shows unavailable/changed presets and preserves stored values until explicitly replaced.
- `test/chord_label_test.dart` covers extension typography, root/bass baselines, literal suffixes, scaling/clipping, styled measurement/anchor alignment, transposition/Nashville projection and instrumental/timing-grid consistency. `test/song_repository_test.dart` covers CRUD, validation, permissions, group isolation, canonical text/ID preservation and published/draft reference safety. `test/song_management_test.dart` covers the forms, source-editor draft navigation, route/membership guards, filtering, setlist selection, reactive Rehearsal resolution and failed-publish handling. `test/anchored_lyric_line_test.dart` covers minimal spacing, adjacent/mid-word/slash chords, word/grapheme wrapping, typography/width changes, transposition and unchanged canonical anchors. `test/floating_sections_test.dart` covers immediate jumps, repeated occurrence identity, scroll highlighting, fixed overlay positioning, state-preserving visibility, safe areas and independent scrolling on narrow/scaled and landscape-sized layouts. `test/chord_chart_view_test.dart` covers anchor alignment/collision lanes, wrapping, narrow/scaled layouts, three modes, transformations, timing rendering, repeated-section navigation and personal controls. `test/timing_grid_test.dart` covers meters/subdivisions, association, changes/sustains, markers, mismatches, validation and grid transformations. `test/chordpro_engine_test.dart` covers parsing, exact anchors, metadata/directives, grids, malformed input, transposition/spelling, Nashville, display modes and every mock arrangement/setlist item. `test/rehearsal_test.dart` covers direct card navigation, first-song order, drawer/swipe selection, scroll reset, section navigation, draft permissions, editor reuse, management deletion refresh, empty/missing setlists and missing arrangements. No integration tests exist. The declared Flutter lower bound does not guarantee compatibility with current API usage.

## File map

Paths below are relative to `lib/`; every Dart file with non-whitespace content is included. Grouped filenames share the stated directory.

| Directory | Files and purposes |
| --- | --- |
| root | `main.dart`: ProviderScope entry point; `firebase_options.dart`: generated platform configuration (Linux unsupported), unused by bootstrap |
| app/ | `bootstrap.dart`: initialize bindings/runApp; `app.dart`: themed router app |
| core/models/ | `app_user.dart`: profile/copy; `user_role.dart`: roles/permission getters; `session_state.dart`: auth/group/loading/error; `group_member.dart`: member/role/join date; `worship_group.dart`: group/members/accent; `song.dart`: song metadata/arrangements/shared presets; `arrangement.dart`: tempo/meter/source/reference URL; `vocalist_key.dart`: singer/key pair; `setlist.dart`: published/draft service model; `setlist_item.dart`: song/arrangement/key/selected vocalist reference; `chart_settings.dart`: preferences/display modes |
| core/mock_data/ | `mock_users.dart`: user fixtures/record type; `mock_groups.dart`: groups/membership/user lookup; `mock_songs.dart`: songs/arrangements/ChordPro; `mock_setlists.dart`: relative-date service fixtures |
| core/router/ | `route_paths.dart`: route constants/helpers; `app_router.dart`: routes/redirects/legacy router session; `router_refresh.dart`: auth-session change notifier |
| core/theme/ | `app_colors.dart`: palette; `app_typography.dart`: Inter text styles; `app_theme.dart`: light/dark themes; `theme_providers.dart`: theme controller/provider |
| features/auth/data/ | `auth_repository.dart`: contract/result; `mock_auth_repository.dart`: delayed fixture sign-in/out |
| features/auth/providers/ | `auth_providers.dart`: repository injection, AuthController/session and derived providers |
| features/auth/screens/ | `login_screen.dart`: branding/sign-in/loading/errors |
| features/groups/data/ | `group_repository.dart`: contract; `mock_group_repository.dart`: streams/role mutation/stub join/create |
| features/groups/providers/ | `group_providers.dart`: repository, groups, membership and role providers |
| features/groups/screens/ | `group_selection_screen.dart`: selection/stub join-create/DEV controls; `group_members_screen.dart`: member list/role changes |
| features/setlists/data/ | `setlist_repository.dart`: contract; `mock_setlist_repository.dart`: in-memory stream/CRUD/draft/publish and current song-reference guards |
| features/setlists/providers/ | `setlist_providers.dart`: repository/detail/list/filter/next-service providers |
| features/setlists/screens/ | `setlists_screen.dart`: list/create/refresh; `setlist_editor_screen.dart`: metadata, song ordering/configuration, song-level preset selection, nested Song Editor, draft/publish/duplicate/delete |
| features/setlists/widgets/ | `setlist_card.dart`: service summary/navigation; `setlist_filter_bar.dart`: filters; `upcoming_service_card.dart`: next-service summary |
| features/songs/data/ | `song_repository.dart`: scoped contract/session/error types; `mock_song_repository.dart`: authorized operations and shared immutable catalog; `song_validation.dart`: form/repository validation |
| features/songs/providers/ | `song_catalog_provider.dart`: shared catalog lifetime; `song_providers.dart`: repository, scoped stream/lookups and permissions |
| features/songs/screens/ | `song_library_screen.dart`: reactive search/category list; `song_details_screen.dart`: read-only song metadata, arrangements and presets; `song_editor_screen.dart`: song form/arrangement management; `arrangement_editor_screen.dart`: arrangement metadata/reference and read-only source form; `basic_chordpro_editor_screen.dart`: full-screen editor, preview and typed draft-return boundary (legacy filename) |
| features/songs/widgets/ | `chordpro_source_field.dart`: read-only source/editor entry with preset/meter context; `chordpro_editing_controller.dart`: cached lexical highlighting, selection-aware insertion and undo/redo; `song_action_helpers.dart`: delete confirmation and feedback |
| features/charts/models/ | `chart_document.dart`: immutable chart/anchor/directive and display projection types; `chord_symbol.dart`: note/key/chord parsing, spelling and degree conversion |
| features/charts/data/ | `chordpro_parser.dart`: source parsing; `timing_grid_parser.dart`: optional explicit-grid attachment/validation; `chart_transformer.dart`: transposition/display/preparation API; `source_chart_adapter.dart`: existing display-only section grouping |
| features/charts/widgets/ | `chord_chart_view.dart`: shared continuous renderer, measures and floating parsed-section navigation; `anchored_lyric_line.dart`: measured horizontal lyric expansion, safe wrapping and coincident-anchor fallback lanes; `chord_label.dart`: shared baseline-aware superscript labels and metrics; `source_chart_view.dart`: retained legacy preview |
| features/charts/providers/ | `chart_providers.dart`: personal arrangement transpose offsets |
| features/rehearsal/screens/ | `rehearsal_screen.dart`: async loading/fallbacks, selected song, toolbar, song drawer and swipe navigation |
| features/profile/screens/ | `profile_screen.dart`: profile/preferences/session actions; `chart_settings_screen.dart`: settings controller/provider and preference controls |

Whitespace-only placeholders excluded from the inventory: `core/widgets/{app_scaffold,empty_state,loading_overlay,primary_button,role_selector_sheet,section_header,status_chip}.dart`, `features/songs/widgets/song_card.dart`.
