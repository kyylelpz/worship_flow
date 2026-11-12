# WorshipFlow

## Overview

**Every Note for His Glory**. A Flutter worship-team planning app with a Firebase Authentication/profile/group and email-invitation foundation and group-scoped Firestore Song/Arrangement/Setlist persistence, local draft editing, account-scoped navigation restoration, ChordPro editing and Rehearsal features. Firebase services require the Console/deployment setup below; this checkout does not deploy them automatically.

## Tech stack

`pubspec.yaml`: app version `0.1.0`, unpublished; Dart `>=3.4.0 <4.0.0`, Flutter `>=3.22.0`. Dependencies: Flutter SDK, `firebase_core: ^5.1.0`, `firebase_auth: ^7.0.1`, `cloud_firestore: ^7.1.0`, `google_sign_in: ^7.2.0`, `flutter_riverpod: ^2.5.1`, `go_router: ^17.5.0`, `google_fonts: ^8.2.1`, `intl: ^0.20.3`, `uuid: ^4.4.0`, `shared_preferences: ^2.5.6`, `drift: ^2.35.3`, `drift_flutter: ^0.3.1`, `metronome: ^2.0.13`. Development: Flutter test SDK and `flutter_lints: ^6.0.0`. These are declared constraints, not resolved versions.

Analyzer fixes were verified with Flutter **3.44.6 / Dart 3.12.2**. Current radio/reorder APIs require a newer Flutter than the declared minimum; the minimum was not changed. Themes use Material widgets and Inter typography through Google Fonts.

## Architecture and implemented scope

- `lib/app/`: existing Firebase options initialization, debug-only emulator/mock configuration, startup-failure UI and themed router app; `main.dart` installs Riverpod ProviderScope.
- `lib/core/`: immutable-style models, mock fixtures, routing, colors, typography, and theme state. Shared widget files are whitespace-only placeholders.
- `lib/features/auth/`: Google Sign-In (Android/iOS/macOS and Web popup), persistent Firebase auth/profile restoration, cancellation/network errors, profile completion and sign-out. Firebase SDK access stays in repositories.
- `groups/`: own-membership group streams, selection, atomic group creation, opt-in email invitations and Administrator-only role/position/removal management. Creator becomes Administrator atomically. Roles and positions remain independent.
- `setlists/`: group lists, upcoming/previous/draft filters, next-service card, details, creation, duplication, deletion, metadata editing, song selection/reordering/removal, arrangement/key selection, explicit atomic draft saving/publishing in Firestore; new forms create no document until saved.
- `songs/`: reactive group-scoped CRUD, search/category filters and read-only details with no actions (favorite toggle removed). Songs own title, artist, category, favorite and shared Vocal Key Presets. Arrangements own name, BPM, meter, optional reference URL and canonical source; the source is read-only in the arrangement form and edited through the full-screen highlighted ChordPro editor. Referenced deletion is blocked.
- `profile/`: required profile completion, Allow Invitations preference, invitation requests/acceptance notifications and account/group display, group switching, sign-out, chart preferences and theme selection. Preferences persist locally per Firebase UID; the shared rehearsal renderer consumes lyric/chord/header font sizes, global scale, line spacing, chart width, display mode and Standard/Nashville notation.
- `charts/`: pure Dart ChordPro parser, typed chart/chord models, transposition and display projections, explicit optional timing grids and a shared Flutter renderer with fixed right-side floating parsed-section bubbles. The old source adapter/viewer remains available for compatibility. `rehearsal/`: actual setlist player screen with a song drawer and horizontal song switching.

## State and data flow

Feature repositories use Riverpod injection. Auth/group default to FirebaseAuthRepository and FirestoreGroupRepository; Song/Setlist repositories default to Firestore implementations in production; explicit mock repositories remain for development/tests. AuthRepository retains sign-in/out/current-user APIs with separate persistent-auth and rule-validated profile capabilities. AuthController owns restoration/loading/errors, current profile and selected group. Firebase auth persists natively and uses local persistence on Web. Active selection is session-local; UID-scoped local preferences restore the last authorized group/setlist/song after authentication. Sign-out clears active state, retaining only that account’s local navigation IDs.

GroupRepository retains its read APIs; GroupCreationRepository adds position/request-ID creation. Production watchGroups is scoped to the current user, not a global directory. It listens to the owner membership index and authorized group/member snapshots, ignoring cached-only snapshots. Permission lookups use server reads. Current role derives from the selected membership, never a profile/global auth role. Revocation/errors clear the selection. Membership changes are rule-validated transactions; the legacy joinGroup boundary does not accept codes. InvitationRepository owns invitation/privacy/member operations.

Setlist filter state derives sorted lists from the selected group's stream. Upcoming/previous include published setlists; drafts include drafts and published setlists with draft changes. Published rehearsal uses `publishedItems`; the editor loads `draftItems ?? publishedItems`. Rehearsal previews draft-only items for roles with `canManageSetlists`; those roles can also toggle Preview Draft in a published setlist’s drawer. Default playback always uses published items. Other roles see an unpublished-state message for draft-only setlists. Publishing copies draft items into published items and clears the draft. Metadata edits remain local until an explicit commit; saved metadata is shared (there is no second published metadata copy).

`songRepositoryProvider` injects `FirestoreSongRepository`; only explicit development/test group repositories select `MockSongRepository` / `InMemorySongCatalog`. `groupSongsProvider` subscribes to the selected group's authorized catalog and restarts on session/membership changes; `songsListProvider` and `songByIdProvider` derive reactive lookups. Library, details, editor, setlist selection/details and Rehearsal now use these providers. Only the development catalog seeds `mockSongs`; real groups start empty. Search/category state remains in the library screen; unavailable categories fall back to All after group/catalog changes. Theme and chart settings use UID-persisted `StateNotifierProvider`s; theme defaults to light. Chart settings include typography, scale, spacing, width, Nashville notation and display mode; reset resets chart settings, not theme.

Routing reads the auth session and membership providers: restoration shows /session-loading, unauthenticated users go to Login, incomplete profiles must finish /profile/complete, completed users choose a group, and selection opens Setlists. Revocation/sign-out returns to the appropriate gate. The legacy router-local session is not used for redirects.

## Navigation

Initial route is /login with restoration/profile/group gates above. Song routes retain repository authorization and Setlist editing retains role guards. Members is accessible from Profile for the current group. Non-Administrators can view members but cannot open functional management forms. Profile is also accessible without a selected group.

| Route | Destination |
| --- | --- |
| `/session-loading` | Firebase authentication restoration |
| `/profile/complete` | Required profile completion |
| `/login` | Login |
| `/groups` | Group selection |
| `/groups/:groupId/members` | Group member list, Administrator invitation/edit/removal actions |
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

Rehearsal uses the exact referenced arrangement and `ChartTransformer.prepare`: numbered source resolves directly in the shared item key, known-source letter chords transpose to it, then the separate personal offset applies once. `ChordChartView` remains navigation-independent. Display mode, personal transpose (+/−12), typography, notation and pinned floating-section controls retain existing behavior. Personal offsets are UID-persisted Riverpod state keyed by arrangement ID; they never modify canonical strings or shared setlist keys. Invalid key requests show an unavailable-chart message; empty charts show a content fallback.


## Roles and permissions

| `UserRole` | Manage members | Manage songs/setlists |
| --- | --- | --- |
| `administrator` (Administrator) | Yes | Yes |
| `worshipLeader` (Worship Leader) | No | Yes |
| `worshipTrainee` (Worship Trainee) | No | No |

Permission getters retain Administrator, Worship Leader and Trainee behavior. Firebase-mode current role comes from the selected membership; client profile/auth data cannot elevate it. Song operations also recheck authenticated membership after asynchronous work. Firestore content rules enforce these permissions using actual group memberships, including deletion-reference protection.

DEV role switching and legacy session/profile injection only work with explicit development mocks. Firebase mode hides the FAB and rejects these methods. WF_USE_MOCKS=true is honored only outside release builds and skips Firebase initialization. Tests opt into mocks explicitly instead of falling back when Firebase is unconfigured.

## Firebase foundation — Spark Phase 3B

Existing project `worship-flow-f3166`, Standard Native `(default)` database in `asia-east2` (free-tier eligibility confirmed). Google Firebase Authentication and Firestore are the only runtime backend services. Cloud Functions, its Flutter dependency, callable implementations and invitation-code UI were removed. No paid service, external email delivery or invitation codes are required. Production never falls back to mocks.

### Schema and authorization

| Path | Data / access |
| --- | --- |
| `profiles/{uid}` | Owner-only document gets; first/last name (max 80), verified Google email, completion flag, `allowInvitations`, creation/update/completion timestamps. No global role or invitation code. Owner writes use strict schema and verified token email. |
| `emailDirectory/{lowercaseEmail}` | Only `uid`; owner opt-in registration/deletion atomically accompanies profile preference. Exact document lookup, never collection queries/listing. |
| `directoryAccess/{uid}` | Owner's lookup context `{groupId}`. Rules verify actual current Administrator membership both when writing this context and on each email lookup; this document grants no role. |
| `groups/{groupId}` | Name (max 120), church (max 160), immutable creator/creation timestamp/accent/legacy `memberCount`; `administratorUid` witness and updated timestamp. Member-only gets, no global list. Counts shown in UI derive from actual member snapshots, not the legacy stored count. |
| `groups/{groupId}/members/{uid}` | UID/groupId, first/last-name snapshots, role, position/customPosition, creation/update timestamps. Members can read/list. Membership is role authority. |
| `profiles/{uid}/memberships/{groupId}` | Owner-only index with uid/groupId/timestamps, atomically created/deleted with the actual membership. No client-controlled role index. |
| `profiles/{recipientUid}/invitations/{groupId}` | Group ID/name snapshot, recipient/inviter UID, role, position/customPosition, random notification ID, `pending`/`accepted`/`declined` status and timestamps. Recipient reads/lists own requests; current group Administrators may get the exact invitation. No email stored here. |
| `profiles/{inviterUid}/notifications/{notificationId}` | Recipient UID, group ID/name, creation time and nullable `readAt`. Owner reads/listens/dismisses; only atomic invitation acceptance can create one. |

Roles: `administrator`, `worshipLeader`, `worshipTrainee`. Positions: `vocalist`, `acousticGuitar`, `electricGuitar`, `bassGuitar`, `keyboard`, `drums`, `other` (custom text required, max 80). Positions never grant permissions. `AppUser.instrument` and session/global role remain development compatibility fields, not production authority.

Profile completion defaults Allow Invitations to enabled. Existing Phase 3A profiles acquire this field and an opt-in directory entry on their next successful account restoration. Disabling it atomically deletes discovery; rules also deny new invitations to that profile even when an Administrator already knows its UID. Pending requests remain available and can be accepted or declined. Private profile documents never become readable by an inviter.

Group creation transaction uses the per-form request ID as the new group ID, creating only a new group, creator Administrator membership and owner index together. Retries return the already-created ID; there is no server quota or payload-hash receipt. No client may directly add arbitrary members to existing groups.

An Administrator enters the recipient's registered verified Google email, selects role/position, and sends a pending in-app request. Rules reject self, duplicate pending and existing-member invitations, and validate all assignment/group snapshots. A request can be reissued after decline or after a formerly accepted member is removed. Recipients confirm Accept/Decline in Profile or Group Selection. Accept transaction writes the immutable assigned membership, owner index, accepted status and inviter notification together. Decline writes only declined status. Replays, partial acceptance, altered assignments and forged notifications are denied. Pending acceptance requires the inviter still to be an Administrator; if that authority is revoked, the recipient can decline and request a new invitation from a current Administrator.

Profile shows unread acceptance notifications and requests; the Setlists Profile icon displays a badge when either is present. Notifications can be dismissed. An Administrator can edit role/position or confirm removal. The UI keeps one's own role fixed; rules additionally prevent unauthorized self-promotion. Removing membership must delete its index atomically. The group's `administratorUid` is a witness pointing to a real surviving Administrator, not an independent grant of authority. Rules use `getAfter` to require that witness still be an Administrator after membership changes. Removing/demoting the witness requires transferring it to another actual Administrator atomically; concurrent changes cannot eliminate all Administrators. Legacy groups acquire this witness during their first Administrator invitation/management transaction.

### Privacy and operational limitations

Exact email lookup **is not private email resolution**: an authorized Administrator who guesses an opted-in registered email can learn its UID/registration. Email addresses are document IDs in the opt-in directory. Collection listing/filter queries are denied, and non-Administrators cannot perform other-user lookup, but Firestore rules cannot impose effective per-user lookup/invitation rate limits. No hashing is claimed to prevent guessing. App Check is not provisioned/enforced. Review this privacy tradeoff before broad distribution.

Requests/notifications/memberships persist in Firestore across sign-out, restarts and offline periods. The existing Firestore disk-persistence setting remains disabled; cached in-session snapshots may remain visible, but transactions require connectivity. Invitation flows do not use the SQLite content cache; there is no synchronization or queued offline acceptance: reconnect and retry to commit a decision. Active group selection is restored through UID-scoped navigation preferences; theme/chart preferences also persist locally per UID. No invitation email is sent. Unregistered or opted-out recipients receive no new invitation; the UI gives a generic unavailable-recipient message.

Rules default-deny legacy `accountPrivate`, `invitationCodeReservations`, server quotas and legacy top-level Song/Setlist paths; group-scoped content paths are enabled by Phase 3C. Existing legacy secret documents, if any, are not used or exposed; remove them manually if desired. Current query shapes are own membership-index collection, member collection under an authorized group, own invitations with `status == pending`, and own notifications with `readAt == null`; only single-field indexes are needed. `firestore.indexes.json` therefore has no composite indexes. Document reads used to validate rules count toward Firestore usage; Spark quotas still apply. These are prototype rules requiring review, not an exhaustive security guarantee.

### Manual configuration and deployment

1. Keep the existing Standard database and enable **Google** in Authentication → Sign-in method; choose support email. Register Android debug/release SHA-1/SHA-256 and download refreshed `android/app/google-services.json` with Web OAuth client (`client_type: 3`), or provide its public ID through `WF_GOOGLE_SERVER_CLIENT_ID`. The original config contained zero OAuth clients. See [Flutter Google authentication](https://firebase.google.com/docs/auth/flutter/federated-auth).
2. For iOS/macOS configure bundle IDs, plist, reversed-client URL scheme, Google IDs/signing/keychain capabilities. `WF_GOOGLE_CLIENT_ID` / `WF_GOOGLE_SERVER_CLIENT_ID` support public client IDs. Web uses Firebase popup auth; authorize actual hostnames and `localhost`. Native Windows Google sign-in is unsupported; use Web. Linux Firebase configuration and Apple builds are unverified.
3. Review the rules and deploy only Firestore configuration (no Functions deployment or billing upgrade):

   ```powershell
   firebase deploy --project worship-flow-f3166 --only "firestore:rules,firestore:indexes"
   ```

   If obsolete Phase 3A Functions were previously deployed, disable/delete those endpoints in Firebase Console before using these client-authorized workflows; removing local source does not delete an already-deployed Admin SDK endpoint. Legacy endpoints bypass Firestore rules. No production resources were deployed/deleted automatically.
4. Manually verify real Google OAuth/persistence, profile completion, opt-in/out, two-account invitations, accept/decline, multiple groups, notification dismissal, role/position changes and last-Administrator protection. Production OAuth and this deployment were not performed by this task. Existing Phase 3A profiles/groups remain readable and are adopted as described above. Names in existing member snapshots are not propagated on later account-name edits.

### Local validation

```powershell
npm --prefix firestore_tests ci
firebase emulators:exec --only firestore --project demo-worship-flow "npm --prefix firestore_tests test"

# App emulator project must match the existing Flutter Firebase options.
firebase emulators:start --only auth,firestore --project worship-flow-f3166
flutter run --dart-define=WF_FIREBASE_EMULATORS=true

# Explicit development fixtures, non-release only.
flutter run --dart-define=WF_USE_MOCKS=true
```

Emulator host defaults to Android `10.0.2.2`, otherwise `127.0.0.1`; physical devices can set `WF_EMULATOR_HOST`. Test code refuses non-emulated Firestore. Rules tests cover exact queries, anonymous/unverified/non-Google denial, private profiles/directory listing, atomic profile/group creation, privacy, duplicate/self invitations, acceptance assignment/index/notification consistency, replay/forgery, independent groups, unauthorized role changes, removal, revocation and concurrent last-Administrator protection. Flutter tests cover privacy, request confirmations, notifications, invite validation, independent roles/positions, management gates/revocation and narrow scaled layouts, alongside retained auth/profile/navigation/rehearsal regressions.

No member invitation codes, external email service, Functions, offline synchronization, revision history, import/export or later backend phase is included. Explicit mock mode keeps fixtures; Firebase invitations are not simulated there; the existing development role menu remains available.

## Mock data

- Users: `user-1` Jordan Rivera (Acoustic Guitar), `user-2` Avery Chen (Keys), `user-3` Noah Patel (Drums); example.com emails and initials are fixtures.
- `group-1`, Grace Community Worship / Grace Community Church: Jordan Administrator, Avery Worship Leader, Noah Worship Trainee. `group-2`, Riverside Youth Band / Riverside Chapel: Jordan Worship Leader, Avery Administrator. Join dates are relative to fixture initialization.
- Each of the two fixture groups starts with an independent copy of the same eight songs/arrangement IDs, preserving existing setlist references. Ownership is stored by group in the catalog rather than adding fields to the public models; new IDs use UUIDs and changes do not propagate between groups. All seed songs are credited to WorshipFlow Originals, with embedded ChordPro and favorite/category metadata:

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

Limitations: not a complete ChordPro specification implementation. Standalone directives are recognized; inline/malformed directives remain literal. Unknown chord text, unsupported directives and tablature are preserved, not interpreted. There is no tablature transposition, fretboard/capo realization, automatic chorus expansion, polychord/microtonal analysis, general ChordPro rhythmic-grid interpretation beyond the explicit WorshipFlow extension below, key-modulation-aware transformations, or harmonic/melodic-minor inference. Bare lines consisting entirely of supported chord/layout tokens are treated as chord-only lines (so a lone `A` is ambiguous). Offsets count UTF-16 code units, not rendered pixels/graphemes; the renderer measures anchors and stacks colliding labels without changing offsets. Target-key transposition needs a known source key; Nashville needs a key; invalid explicit keys or mismatched references raise `ArgumentError`. Source metadata remains canonical while `ChartDocument.key` records the effective transformed key.

## Chart renderer and timing grids (Phase 2B)

`ChordChartView` renders a continuous vertical scroll, never pages. Lyrics + Chords measures each rendered lyric segment and chord label with Flutter text metrics. When distinct chord anchors would collide, the layout inserts the measured horizontal deficit plus a font-size-aware minimum clearance of max(8dp, effectiveChordFontSize × 0.5), preserving chord-to-lyric alignment. This is display geometry only: canonical source, lyric strings and UTF-16 anchor offsets are unchanged. Expanded lines stay on one chord row when they fit; words wrap first, then oversized words split at chord anchors and grapheme boundaries. Chords sharing the exact same lyric offset retain a last-resort vertical lane because both must remain anchored to the same character. There is no longer a separate chord-width gutter; the narrow section-button overlay gutter remains independent. Lyrics Only retains text/sections and hides chords. Chords Only renders explicit valid timing grids where available, otherwise ordered chord sequences labelled **no timing**. Blank lyric lines and repeated parsed sections are retained. Font sizes, global scale and system text scaling apply; a chord symbol wider than the entire available line may wrap within its label. Layout is remeasured on font/style, system scale, transformation or viewport changes. The renderer supports left-to-right chart layout; complex bidirectional layout, printing and pagination are not implemented.

### Floating section navigation (Phase 2B.2)

The old left rail is removed from `ChordChartView`. Rounded section buttons form a fixed overlay at the upper-right of the chart viewport, below the pinned font controls. Short labels include IN, V1, CH, BR and OUT. Repeated abbreviations receive occurrence numbers (for example CH1/CH2 or V1·1/V1·2); full-label tooltips and accessibility descriptions include their ordered section position. Parsed IDs and existing `Scrollable.ensureVisible` anchors are retained; jumps have zero animation duration.

The active bubble updates after manual scrolling becomes idle, and recomputes after viewport, text-scale or chart-setting changes. Programmatic jumps highlight immediately; Editor Preview disables section tracking and measurements entirely. The last section becomes active at the chart bottom. The bubble stack has 48-pixel minimum touch targets, uses the current theme, respects side/bottom safe areas, and is bounded to 360 pixels or the available viewport height. Longer lists scroll independently of the chart. A narrow right gutter reserves overlay space even while hidden, so Hide/Show affects only the bubbles: lyrics do not rewrap and chart scroll, song selection, personal transpose and preferences remain unchanged. The visibility choice persists during song switching within the current Rehearsal screen. Horizontal song swipes and the setlist drawer retain their existing behavior. Buttons are not draggable. The translucent settings overlay is not implemented.

Optional timing grids live in the **same canonical arrangement source**, alongside lyric sections. Supported WorshipFlow syntax:

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

- `TimingGrid`, `TimingMeasure` and `TimingSlot` represent measures, explicit equal-duration slots, chord-change events and sustains. A chord starts a new event; `-` sustains the previous event, including across measures/rows. A leading `-` is a rest until the first chord activates. No durations are inferred from lyric anchors.
- `{time: 3/4}`, `{time: 4/4}` and `{time: 6/8}` are supported. `{grid_subdivision: N}` allows integers 1–8 subdivisions **per denominator-note beat**, default 1. Thus 4/4 with subdivision 2 needs eight slots per measure, 3/4 needs six, and 6/8 needs twelve. 6/8 at subdivision 1 explicitly means six eighth-note slots, not two inferred dotted-quarter beats. Parsed documents default to 4/4 when no meter is supplied; `prepare` uses the arrangement time signature as fallback. Directives apply in source order; changes within one grid are flagged unsupported.
- Multiple changes are supported, for example `| D - G - |` in 4/4. Bare and bracketed chord names work. Enclosing bars are required. Bar/repeat markers such as `|:`, `||` and `:|`, repeated measures, original rows and canonical source are retained; repeat playback/expansion and `%` measure-repeat shorthand are not implemented.
- A labelled grid associates with the nearest preceding lyric section of the same normalized label, or the first following match. Repeated labels retain distinct IDs; an unmatched grid is a standalone instrumental section. In Chords Only, associated valid grids appear under their lyric section; the separate grid section is not duplicated in section navigation. Other modes retain lyric content, with standalone instrumental chord passages where applicable.
- Lyric and grid chord-change sequences are compared using pitch, quality and bass, coalescing consecutive identical events. Differences produce visible warnings; neither source representation is rewritten. Chords Only chooses the explicit valid grid; lyric modes retain lyric anchors. Invalid counts, meter/subdivision, tokens, and missing bars warn and fall back to untimed sequences where parsable. These checks are conservative, not automatic musical synchronization.
- Grid chords transpose and convert to Nashville through the same engine operations as lyric chords. Valid grid slot duration is available in whole-note units. Timing slots use the shared compact measured-column grid, with distinct barlines and complete-measure wrapping; no measure cards or beat-number rows are displayed. Wrapping changes screen layout only, not event timing.

There is no playback clock, metronome, tempo automation, tuplets, variable-duration slot syntax, nested sections/repeats, polyrhythm, inferred rhythmic alignment. Unknown/malformed source remains canonical; unsupported timing is reported instead of fabricated.

## Song library CRUD (Phase 3A)

- `SongRepository` provides authorized catalog streams/lookups, song create/update/delete and arrangement create/update/duplicate/delete. `Song.copyWith` and `Arrangement.copyWith` support immutable edits while preserving IDs. Song metadata saves cannot replace the arrangement collection; arrangement operations have their own methods. Repository snapshots freeze arrangement/preset lists.
- Creating a song requires at least one valid arrangement. Existing song metadata is saved with **Save Song**; arrangement actions on existing songs save immediately, as stated in the editor. New-song arrangements remain local drafts until the song is created. Opening Add Song pushes onto the library history; successful creation pops Add Song back to the existing Song Library to retain its Setlists history, falling back to the library route only when no previous page exists. Song Library always exposes Back and falls back to Setlists for direct access, including Android Back. Add/Edit Song exposes an explicit Back button and shares discard confirmation with Android Back for unsaved metadata or new-song arrangement drafts. With no previous page, Back falls back to Song Library. Group changes block an already-open metadata editor from saving into another group's catalog.
- Song validation requires title, artist and category; the editor offers Praise, Worship, Communion or Other with required custom input. Vocal Key Presets are song-level, with required names/major-or-minor keys and case-insensitive unique names. Arrangements require name, source, integer BPM 1–400 and meter 3/4, 4/4 or 6/8; an optional reference link must be http(s) with a host. Song default key and Arrangement performance key were removed. Source is never automatically trimmed, transposed or rewritten; full source linting remains deferred.
- Song/arrangement deletion requires confirmation. `SetlistSongReferences` supplies that immediate lookup in development mocks; production uses Firestore catalog guard transactions across both versions. Referenced records cannot be deleted; a song must keep one arrangement. A referenced letter-source arrangement cannot switch its known source major/minor mode; duplicate it instead. Edits retain IDs and existing setlist performance keys remain unchanged.
- The production mock setlist provider wires the shared catalog's synchronous `validateReferences` into draft saves. A song/arrangement deleted after selection in an unsaved editor causes a clear save error; Publish stops after a failed save. Removing references in the normal setlist editor permits later deletion. A repository without reference-check capability fails closed for destructive song operations.
- `ArrangementEditorScreen` edits name/BPM/meter/reference URL and shows read-only canonical source with Edit navigation. `openChordProEditor` returns draft text; only Save Arrangement (or creating the new Song) persists it. Vocal presets are edited/saved with Song metadata. The general Song Editor is reused from setlist configuration and the Rehearsal popup; saving pops to its existing caller. Song Details lists metadata, arrangements and shared presets without raw source or arrangement mutation menus.
- Success/error snackbars and form validation provide feedback; newer arrangement-operation feedback replaces earlier snackbars. Production data persists through the Firestore repositories described below. Explicit development mocks retain provider/container-lifetime storage.

### Setlist configuration and key ownership

Newly added items require explicit selection of a song Vocal Key Preset; no arbitrary key is assigned. Configuration keeps arrangement selection independent of the key and displays `Vocalist · Key` choices. Songs without presets offer Edit Song to add one; Done requires an available arrangement and a key. Existing stored keys remain usable even if their preset changes/disappears. Editing a Song in the configuration sheet refreshes metadata/presets without losing the unsaved setlist name, order or item selection. Reference validation rejects missing songs/arrangements and invalid or unset item keys before saving. Production setlists use the versioned Firestore transactions below; development fixtures remain in memory.

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

## Firestore content and local restoration — Phase 3C

### Schema and repository behavior

| Path / location | Data and behavior |
| --- | --- |
| `groups/{groupId}/songs/{songId}` | Immutable `id`/`groupId`/`createdAt`; title/artist/category/favorite, song-level vocal presets; `arrangements` map keyed by stable IDs plus ordered `arrangementIds`. Each arrangement has name, BPM, meter, exact canonical `chordProSource`, optional reference URL. `arrangementChanges` is a rule-checked map-diff key list, not a second chart. `updatedAt` uses server time. |
| `groups/{groupId}/catalog/{arrangementId}` | Reference guard: immutable song ownership, `uses` setlist-ID list, last-operation `target` ID and server `updatedAt`. Exact gets only; no global directory. Created/deleted atomically with the arrangement. |
| `groups/{groupId}/setlists/{setlistId}` | Immutable IDs/group/creation time; name, service Timestamp, status, ordered `publishedItems`, nullable ordered `draftItems`, `publishedKeys`/`draftKeys`/union `referenceKeys`, incrementing `revision`, server `updatedAt`. Items retain song ID, exact arrangement ID, performance key and nullable selected vocalist name. |
| Local `wf.resume.{uid}` preference | JSON group/setlist/song IDs only. No chart scroll, credentials, document data or cross-account global resume key. Writes are serialized; malformed saved IDs are ignored. |

`FirestoreSongRepository` preserves metadata-only updates, stable existing IDs, arrangement duplicate/delete behavior and source text without normalization. One group song collection stream feeds Library, setlist selection and Rehearsal. Song metadata edits read the song once; operations needing reference safety read the affected guard documents. Existing interfaces remain; mocks are selected only through explicit development/test backends. No real group is seeded from fixtures, and prior in-memory data is not silently uploaded.

`FirestoreSetlistRepository` streams the selected group collection. Detail/Rehearsal providers derive updates from that stream. Direct server reads support initial resume validation. `AtomicSetlistRepository.commitSetlist` supplements the legacy contract so an editor commits name/date/items/status/reference guards in one transaction. Revision checks reject a stale editor or remotely deleted setlist while keeping local edits. Service dates remain instants displayed in device-local time, preserving existing date/time semantics; no new service timezone model is introduced.

### Draft lifecycle and exit behavior

New Setlist opens `/setlists/new/edit` with local fields and no document. Existing editors load a local copy of `draftItems ?? publishedItems`; remote streams never overwrite that unsaved editor state. Save Draft commits the current name/date/items once, retaining any published items/status. Publish commits the intended published items and clears draft items atomically. Default Rehearsal reads published items; authorized managers can explicitly Preview Draft from the drawer. Both versions retain their own order, arrangement references, performance keys and vocalist selections.

Toolbar Back, Android Back and GoRouter exits use **Save Setlist as Draft?** with **Save as Draft**, **Discard Changes**, **Cancel**. Save validates/commits before leaving; Discard leaves with no write; Cancel stays. Clean forms leave normally. Actual field/item snapshots determine dirtiness, so reverting an edit clears the prompt. Save failures retain the editor and actionable feedback. In-progress commits disable controls/navigation and duplicate saves. Authentication/group revocation can still remove protected screens. Nested Song Editor routes do not invoke the parent exit guard or reset its unsaved draft. Saved metadata is shared immediately after the explicit commit; only item versions have separate draft/published copies.

### Reference safety, rules and tested limits

Verified Google group members can read group content; only actual Administrator/Worship Leader membership permits writes. Profiles, memberships and invitation rules retain their previous behavior. Content validators reject extra fields, forged ownership/IDs, invalid types, keys/meters/BPM, and timestamps. Catalog entries bind arrangements to existing same-group songs. Setlist item writes require catalog ownership plus a matching post-transaction use entry. Catalog use changes must agree with the post-transaction setlist manifests. Song/arrangement removal requires deleting the corresponding guard; that guard cannot be deleted while any draft or published setlist uses it. Thus client checks alone cannot authorize deletion, including concurrent save/delete races.

Setlist deletion transaction also removes its use entries. A custom authorized client that deletes only the setlist can leave conservative stale locks, but cannot thereby delete a referenced song. Such a lock can be removed only for a target setlist that no longer references it (or no longer exists). There is no automatic cleanup/member-content deletion service.

The bounded validators have explicit limits to stay within Spark rule-expression/document-access budgets: **6 items per setlist version**, **8 arrangements and 8 vocal presets per song**. Initial song creation accepts **up to 2 arrangements and 4 presets**; additional arrangements/presets can be added after creation. At most two arrangement map entries change in one song write. Charts support up to 200,000 source characters each and the entire song must fit Firestore's 1 MiB document limit. These are new storage limits, not claims of unlimited preservation of the former in-memory capacity. Expanding them requires a different validation/storage layout and new boundary tests. No pagination or offline-first catalog is implemented.

Actual queries are direct group song/setlist collections and exact catalog/membership gets, with filtering/sorting in Dart. **No new composite indexes are needed**; `firestore.indexes.json` remains empty. Catalog guard lists and song documents still have the 1 MiB document limit; there is no global group catalog bottleneck.

### Resume and account isolation

Resume results carry the UID they were resolved for, including empty results. The router waits for the authenticated account’s result before applying restoration, so an anonymous result cached during Firebase startup cannot consume that account’s one-time resume.

After Firebase auth and profile completion, `/session-loading` remains visible while local IDs and current server membership/setlist access are validated. The router applies the result once per authenticated session. Valid saved state opens Rehearsal directly and selects the saved song; a missing song falls back to the first available item. Repeated occurrences of one song restore the first matching occurrence because only Song ID is persisted. Revoked/missing membership falls back to Group Selection; missing/inaccessible setlists fall back to the authorized group's Setlists. Connectivity failures show a retryable restoration state instead of assuming access. Sign-out/account changes cancel the pending restoration and never apply another UID's destination.

Manual Group switching is respected for the current session and updates local group state while clearing the old setlist/song. Opening a setlist or changing its song updates the local IDs. Back to Setlists stays there for that session; a later launch still resumes the last opened setlist. Personal transpose, chart preferences and scroll remain separate; exact scroll is not saved. Firestore disk persistence remains disabled and committed content requires connectivity; no synchronization engine or offline mutation queue was added.

### Deployment and manual verification

Review and deploy only configuration, without changing billing or deploying Functions:

```powershell
firebase deploy --project worship-flow-f3166 --only "firestore:rules,firestore:indexes"
```

No deployment was performed automatically. Install the rebuilt app after adding `shared_preferences`. Verify with two authorized accounts: create/edit songs with exact whitespace/source and presets; create/discard/save/publish/duplicate setlists; see remote updates; prevent referenced deletion; change/revoke roles; relaunch into the last song; delete the saved setlist/revoke membership and check fallbacks. Existing real groups remain empty until users create content. Emulator/widget tests do not prove production deployment, real two-device synchronization, or OAuth configuration.

Validation commands:

```powershell
firebase emulators:exec --only firestore --project demo-worship-flow "npm --prefix firestore_tests test"
flutter test test/firestore_phase3c_test.dart test/rehearsal_test.dart test/song_management_test.dart test/song_refactor_test.dart test/firebase_foundation_test.dart test/invitation_management_test.dart
flutter analyze
flutter build apk --debug
```

The new tests cover canonical codecs, map ordering, group content CRUD/roles, draft versus published references, concurrent deletion, maximum supported sizes, direct-write attacks, Save/Discard/Cancel, no early creation, failed/double saves, nested editing, UID isolation, pending restore races, manual switching, invalid/deleted destinations and last-song selection. Prototype Security Rules still need review before wider distribution.

## Development roadmap (planned)

Chart/editor functionality remains intact. Backend Phases 3A–3C now include authentication, invitations/member management, group content persistence, explicit draft commits and local navigation restoration. Phase 4A adds a SQLite read cache; Offline Rehearsal V1 adds published cached playback; synchronization/revision history and import/export remain deferred. Historical UI phase labels are not the backend rollout schedule.

## Known limitations

- Accounts, groups, memberships, invitations, notifications, songs, arrangements and setlists use Firebase storage. Navigation IDs, theme, chart preferences and personal Arrangement offsets use local UID-scoped preferences. Real new groups start empty.
- The last selected group is restored only after fresh membership validation. Profile editing UI covers first completion; a separate edit-account screen is not implemented. Member display-name snapshots are not propagated on later profile changes. Group role/position updates and invitations are implemented with rule-validated client transactions.
- Live Google OAuth and production deployment require manual setup. Native Windows Google Sign-In is unsupported; use Web on Windows. Linux Firebase options are not configured. Apple platform builds/configuration need Apple tooling and were not verified here.
- Missing setlists display unavailable states. Draft-only songs remain absent from published Rehearsal. Editing a preset does not silently update already-stored setlist keys or vocalist names; configuration shows unavailable/changed presets and preserves stored values until explicitly replaced.
- `test/chord_label_test.dart` covers extension typography, root/bass baselines, literal suffixes, scaling/clipping, styled measurement/anchor alignment, transposition/Nashville projection and instrumental/timing-grid consistency. `test/song_repository_test.dart` covers CRUD, validation, permissions, group isolation, canonical text/ID preservation and published/draft reference safety. `test/song_management_test.dart` covers the forms, source-editor draft navigation, route/membership guards, filtering, setlist selection, reactive Rehearsal resolution and failed-publish handling. `test/anchored_lyric_line_test.dart` covers minimal spacing, adjacent/mid-word/slash chords, word/grapheme wrapping, typography/width changes, transposition and unchanged canonical anchors. `test/floating_sections_test.dart` covers immediate jumps, repeated occurrence identity, scroll highlighting, fixed overlay positioning, state-preserving visibility, safe areas and independent scrolling on narrow/scaled and landscape-sized layouts. `test/chord_chart_view_test.dart` covers anchor alignment/collision lanes, wrapping, narrow/scaled layouts, three modes, transformations, timing rendering, repeated-section navigation and personal controls. `test/timing_grid_test.dart` covers meters/subdivisions, association, changes/sustains, markers, mismatches, validation and grid transformations. `test/chordpro_engine_test.dart` covers parsing, exact anchors, metadata/directives, grids, malformed input, transposition/spelling, Nashville, display modes and every mock arrangement/setlist item. `test/rehearsal_test.dart` covers direct card navigation, first-song order, drawer/swipe selection, scroll reset, section navigation, draft permissions, editor reuse, management deletion refresh, empty/missing setlists and missing arrangements. Firebase foundation/invitation widget tests cover restoration/profile/group/role/privacy/member flows. Firestore emulator tests cover client transactions, atomic invariants and security rules; real native Google OAuth remains a manual check. The declared Flutter lower bound does not guarantee compatibility with current API usage.

## File map

Paths below are relative to `lib/`; every Dart file with non-whitespace content is included. Grouped filenames share the stated directory.

| Directory | Files and purposes |
| --- | --- |
| root | `main.dart`: ProviderScope entry point; `firebase_options.dart`: generated platform configuration (Linux unsupported), used by bootstrap |
| app/ | `bootstrap.dart`: initialize bindings/runApp; `app.dart`: themed router app |
| core/models/ | `app_user.dart`: profile/copy/completion/invitation preference; `user_role.dart`: roles/permission getters; `membership_position.dart`: independent group-position enum; `session_state.dart`: auth/group/loading/error; `group_member.dart`: member/role/position/timestamps; `worship_group.dart`: group/members/accent; `song.dart`: song metadata/arrangements/shared presets; `arrangement.dart`: tempo/meter/source/reference URL; `vocalist_key.dart`: singer/key pair; `setlist.dart`: published/draft service model and revision; `setlist_item.dart`: song/arrangement/key/selected vocalist reference; `chart_settings.dart`: preferences/display modes |
| core/mock_data/ | `mock_users.dart`: user fixtures/record type; `mock_groups.dart`: groups/membership/user lookup; `mock_songs.dart`: songs/arrangements/ChordPro; `mock_setlists.dart`: relative-date service fixtures |
| core/firebase/ | `firebase_providers.dart`: SDK injection/mock flag; `content_codec.dart`: exact Firestore model serialization/deep comparison; `navigation_resume.dart`: UID-scoped preferences and validated restoration |
| core/router/ | `route_paths.dart`: route constants/helpers; `app_router.dart`: routes/redirects/legacy router session; `router_refresh.dart`: auth-session change notifier |
| core/theme/ | `app_colors.dart`: palette; `app_typography.dart`: Inter text styles; `app_theme.dart`: light/dark themes; `theme_providers.dart`: theme controller/provider |
| features/auth/data/ | `auth_repository.dart`: auth/persistence/profile contracts; `google_sign_in_failures.dart`: redacted sign-in diagnostics and distinct error mapping; `firebase_auth_repository.dart`: Google/Firebase auth, profile restoration and rule-validated profile writes; `mock_auth_repository.dart`: development/test fixtures |
| features/auth/providers/ | `auth_providers.dart`: repository injection, AuthController/session and derived providers |
| features/auth/screens/ | `login_screen.dart`: branding/sign-in/loading/errors |
| features/groups/data/ | `invitation_repository.dart`: invitation/notification models and mutation contract; `firestore_invitation_repository.dart`: opt-in discovery, invitations, acceptance and member transactions;  `group_repository.dart`: read/creation contracts; `firestore_group_repository.dart`: own group/member streams and atomic creator bootstrap; `mock_group_repository.dart`: development groups/create/role simulation |
| features/groups/providers/ | `invitation_providers.dart`: own pending/unread streams and repository injection;  `group_providers.dart`: repository, groups, membership and role providers |
| features/groups/screens/ | `group_selection_screen.dart`: scoped selection/empty-state Create; `group_creation_screen.dart`: validated creation/position form; `group_members_screen.dart`: member list and Administrator invitation/edit/removal forms; retained development role menu |
| features/setlists/data/ | `firestore_setlist_repository.dart`: streams, atomic versioned commits and reference guard updates;  `setlist_repository.dart`: existing and atomic commit contracts; `mock_setlist_repository.dart`: in-memory stream/CRUD/draft/publish and current song-reference guards |
| features/setlists/providers/ | `setlist_providers.dart`: repository/detail/list/filter/next-service providers |
| features/setlists/screens/ | `setlists_screen.dart`: list/create/refresh; `setlist_editor_screen.dart`: metadata, song ordering/configuration, song-level preset selection, nested Song Editor, draft/publish/duplicate/delete |
| features/setlists/widgets/ | `setlist_card.dart`: service summary/navigation; `setlist_filter_bar.dart`: filters; `upcoming_service_card.dart`: next-service summary |
| features/songs/data/ | `firestore_song_repository.dart`: persistent group song/arrangement CRUD and guard transactions;  `song_repository.dart`: scoped contract/session/error types; `mock_song_repository.dart`: authorized operations and shared immutable catalog; `song_validation.dart`: form/repository validation |
| features/songs/providers/ | `song_catalog_provider.dart`: shared catalog lifetime; `song_providers.dart`: repository, scoped stream/lookups and permissions |
| features/songs/screens/ | `song_library_screen.dart`: reactive search/category list; `song_details_screen.dart`: read-only song metadata, arrangements and presets; `song_editor_screen.dart`: song form/arrangement management; `arrangement_editor_screen.dart`: arrangement metadata/reference and read-only source form; `basic_chordpro_editor_screen.dart`: full-screen editor, preview and typed draft-return boundary (legacy filename) |
| features/songs/widgets/ | `chordpro_source_field.dart`: read-only source/editor entry with preset/meter context; `chordpro_editing_controller.dart`: cached lexical highlighting, selection-aware insertion and undo/redo; `song_action_helpers.dart`: delete confirmation and feedback |
| features/charts/models/ | `chart_document.dart`: immutable chart/anchor/directive and display projection types; `chord_symbol.dart`: note/key/chord parsing, spelling and degree conversion |
| features/charts/data/ | `chordpro_parser.dart`: source parsing; `timing_grid_parser.dart`: optional explicit-grid attachment/validation; `chart_transformer.dart`: transposition/display/preparation API; `source_chart_adapter.dart`: existing display-only section grouping |
| features/charts/widgets/ | `chord_chart_view.dart`: shared continuous renderer, measures and floating parsed-section navigation; `anchored_lyric_line.dart`: measured horizontal lyric expansion, safe wrapping and coincident-anchor fallback lanes; `chord_label.dart`: shared baseline-aware superscript labels and metrics; `source_chart_view.dart`: retained legacy preview |
| features/charts/providers/ | `chart_providers.dart`: personal arrangement transpose offsets |
| features/rehearsal/screens/ | `rehearsal_screen.dart`: async loading/fallbacks, selected song, toolbar, song drawer and swipe navigation |
| features/profile/screens/ | `profile_completion_screen.dart`: required names/email confirmation; `profile_screen.dart`: account/privacy/invitations/position/preferences/session actions; `chart_settings_screen.dart`: settings controller/provider and preference controls |

| features/profile/widgets/ | `invitation_panel.dart`: privacy toggle, confirmed requests and dismissible acceptance notifications |

`firestore_tests/` contains only development test dependencies and Firestore security/client-transaction tests. `firebase.json`, `.firebaserc`, `firestore.rules` and `firestore.indexes.json` configure the existing project and emulators. Client Firebase config is public configuration, not a server credential.

Whitespace-only placeholders excluded from the inventory: `core/widgets/{app_scaffold,empty_state,loading_overlay,primary_button,role_selector_sheet,section_header,status_chip}.dart`, `features/songs/widgets/song_card.dart`.


### Phase 3D — concurrent editing

Setlist commits retain their existing revision check inside the Firestore transaction. A stale revision or remotely deleted record raises a typed conflict. Reload Latest explicitly discards the local draft and loads the latest draft/published baseline; Keep Editing, Cancel and dialog dismissal preserve it and its original revision. Retrying cannot silently overwrite changes or recreate a deleted Setlist. Failed reloads retain the local draft.

Song metadata and Arrangement editors pass their opening snapshots into transaction-time comparisons. Metadata saves compare metadata/shared vocal presets only and retain current Arrangements; Arrangement saves compare that Arrangement’s exact source and metadata and retain unrelated edits. Failed Arrangement commits now leave the Arrangement editor open, including its source draft. Explicit Reload Latest replaces the local fields; deleted records cannot be recreated through update operations. New-song Arrangements remain local until the parent Song is saved.

This uses existing Spark-compatible transactions, schema, role rules and reference guards, with no deployment or new indexes required. There is no automatic merge, force overwrite, revision history or offline conflict queue. Snapshot comparison detects changed content, not a change reverted to identical content. Legacy repository callers remain compatible; callers implementing an editing workflow must pass `expected` to Song/Arrangement updates. These client conflict checks supplement existing backend authorization; they are not a restriction against a custom authorized client intentionally overwriting content.


### Persistent user preferences

`core/preferences/user_preferences.dart` stores versioned JSON in SharedPreferences under `wf.preferences.{uid}`. It retains theme (light/dark/system), all chart typography/global scale/line spacing/width/display/notation fields, and personal semitone offsets keyed by Arrangement ID. Writes are serialized and capture their owning UID; sign-out does not erase saved preferences. Account changes clear active preferences and restore that account’s values. No anonymous/global settings are copied into a newly signed-in account.

The existing theme/chart controller methods and personal-offset `.notifier.state` controls remain usable. Hydration covers routed content until preferences finish loading while keeping navigation mounted. A late previous-account read is ignored; edits made during a pending read are merged without dropping unrelated saved fields. Chart reset persists chart defaults only; theme reset persists theme defaults only; neither clears personal offsets. Source ChordPro, shared performance keys and Firestore are untouched.

Unknown schema versions and corrupt payloads fall back to defaults. Known-version fields are validated independently against current control ranges; invalid enum names/types/numbers/offsets are ignored. Storage failures leave session controls usable, but may prevent persistence. These are device-local settings, with no cross-device synchronization, scroll-position persistence or settings migration from undocumented legacy formats. `test/user_preferences_test.dart` covers restart, account isolation, resets, invalid data, pending-read races and the startup loading cover.


### Phase 4A - SQLite local read cache

`core/cache/content_cache_database.dart` uses Drift/SQLite with explicit SQL and schema version 1 (no code generation). `drift_flutter` opens `worship_flow_read_cache.sqlite` in the native app documents directory using its database isolate. Two tables retain `(uid, group_id, kind, id, payload)` documents and per-collection refresh timestamps. The JSON payload preserves complete server content, Timestamp seconds/nanoseconds, Song/Arrangement IDs and order, metadata, vocal presets, exact canonical ChordPro whitespace, Setlist revisions, and independently ordered published/draft items and references. The existing content codecs provide typed reads; no shared source text is rewritten.

Production Song/Setlist repositories populate this cache from complete, successfully decoded server snapshots and explicit server document reads. Cache-only snapshots, pending local writes and partial results cannot replace collections. Query errors propagate through the existing providers; they never become empty collections. Validation happens before replacement, and SQLite transactions roll back failed refreshes. Older Setlist revisions or older available server update timestamps cannot regress a newer cached record. Only a successful complete empty server snapshot clears a collection. Confirmed missing documents and successful Song/Setlist deletions remove the corresponding cached record. Cache write failures do not turn a successful Firestore read into a UI failure; `LocalContentCache.lastError` retains diagnostics.

`LocalContentCache` exposes `readSongs`, `readSong`, `readArrangement`, `readSetlists` and `readSetlist` for Offline Rehearsal. Collection reads report completeness and the last collection refresh time; individual server reads do not claim an entire collection is cached. Corrupt rows are excluded with `complete: false`, and a valid subsequent refresh repairs them. A corrupt/unavailable SQLite file raises on local reads rather than claiming an empty authorized collection; automatic physical-file replacement is deferred.

Every operation is keyed by Firebase UID and Group ID. The public local-read boundary derives its UID from Firebase Auth, checks it again after asynchronous work, and rejects known-revoked scopes. Authentication changes invalidate in-flight tokens and queue deletion of the previous account's documents/collection markers; sign-out therefore purges content, unlike the separately retained SharedPreferences navigation/settings. A complete server membership-index snapshot removes groups no longer present, and confirmed missing/mismatched own membership or a complete member list without the user purges that group. Permission/network errors alone are not proof of an empty collection or revoked membership and do not erase cached content. A late remote response cannot repopulate a purged account/group. Rejoining requires fresh confirmed membership before new reads are cached.

Firestore remains authoritative. Transactions, conflict checks, role rules, reference guards, routing/restoration and SharedPreferences are retained. Firestore refreshes content online; Offline Rehearsal V1 adds the read-only cache fallback below. Cache population is demand-driven by existing reads, without background prefetch or additional Firestore listeners. Revocation cannot be learned while disconnected; a locally retained authorization is not a new server permission grant. SQLite is app-sandboxed, not encrypted, and purges are logical deletions rather than forensic secure erasure. If the process terminates during a queued purge, UID/token guards still prevent cross-account reads on restart; records left by interrupted deletion may remain on disk until a later invalidation. Web continues online without this cache: deploying SQLite WASM/worker assets is deferred. No offline editing, queued writes, automatic merge, Firestore schema/index/rules changes, Functions, billing upgrades or deployment are included.

`test/local_content_cache_test.dart` covers native SQLite reopen, source/metadata/reference/revision round trips, UID/group isolation, pending/partial/invalid refresh rejection, atomic rollback, confirmed deletion, membership/sign-out invalidation and late callbacks, malformed rows and physically corrupt database files.


### Compact grids and editor preview controls

`compact_chord_grid.dart` is a shared presentation-only layout for ordinary instrumental passages and parsed timing grids. Each passage measures styled `ChordLabel` labels (including superscripts and text scaling), sizes beat columns independently in each measure, shares a chord baseline, and wraps complete measures according to the available width. Source row boundaries and written measure order are retained; textual `(2x)`/`(4x)` annotations remain visible without expanding repeats. Untimed tokens receive visual columns only, never inferred durations. A single measure wider than the viewport retains user typography and gets horizontal scrolling as a last resort. No parser, timing validation, source normalization or repeat-notation changes are involved.

Lyrics + Chords keeps anchored lyric lines and uses the compact grid for ordinary instrumentals and standalone timing grids; explicit grids associated with lyric sections remain hidden there. Chords Only uses valid explicit slots where available and preserves written untimed sequences otherwise. Lyrics Only is retained. Rehearsal section bubbles, selection, jumps and scrolling remain available.

Editor Preview now uses a 12-chromatic-key selector, initialized from explicit preview context, source key or an available preset; keyless source without any context requires a selection. Minor source context remains minor, with conventional enharmonic target spelling. Vocalist preset chips and the key confirmation button are hidden. Local display controls offer Lyrics + Chords and Chords Only; an existing supported display preference can initialize the mode, while Lyrics Only falls back to Lyrics + Chords. Notation starts Standard for each new editor and can switch to Nashville without resetting key or display mode. Controls update immediately, wrap adaptively and can scroll vertically when accessibility scaling leaves insufficient header space. Preview has no section bubbles or reserved sidebar gutter; Rehearsal retains its existing hide/show behavior. These choices never persist preferences or change source, Arrangement data or vocal presets. Preview still uses current draft text and preserves editor/preview scroll state.

Focused widget coverage is in `compact_chord_grid_test.dart` and `chordpro_preview_controls_test.dart`, with updated chart/editor/Nashville regressions. No persistence or dependency changes are required.


### Offline Rehearsal V1

Previously cached **published** Setlists can open offline for the same verified Google Firebase UID, completed profile and previously verified group membership. The existing SQLite document table additionally stores `profile` metadata (empty group scope, ID = UID) and `access` metadata (group scope, own membership/group details). The SQL schema is unchanged. A V1 online visit must populate this proof: Phase 4A content-only caches cannot grant offline access. Native Firebase must retain the signed-in account; first sign-in/profile completion requires connectivity. Profile startup uses a bounded server timeout before falling back; a known connection failure avoids redundant server checks during saved-navigation restoration.

`LocalContentCache.rehearsal` requires every published item's exact Song/Arrangement and nonempty canonical source. Incomplete, missing, revoked or draft-only bundles show an actionable message, never partial offline playback. The offline Setlists list offers only fully cached published bundles. Missing draft-only references do not block a complete published version. The unchanged engine reconstructs sections locally from exact ChordPro; display modes, notation, personal offsets, typography, section jumps and song switching require no network reads. Offline roles/UI are read-only, including previously privileged members. Online draft preview/editing retains existing behavior.

Cached playback is labeled `Offline · Cached charts · Read only`. Cached mode lasts until profile, membership and both content streams have fresh server confirmation; this label describes cache freshness rather than a separate connectivity-plugin reading. Existing listeners remain attached and refresh SQLite/displayed bundles after reconnection. Refresh retries content/group subscriptions. Server deletions remove cached records; authorization failures invalidate scope instead of falling back. Confirmed membership/group removal purges only that group. Network failures never mean empty collections. The cache-first adapter attaches remote listeners immediately and ignores slow cached results after newer server results; existing revision/update-time guards prevent cache regression.

Sign-out/account switching invalidates and purges protected content/profile/access by UID; SharedPreferences settings/navigation remain separate. Revocation cannot be discovered while disconnected: cached last-known access lasts only until server revalidation. SQLite remains unencrypted/app-sandboxed; abrupt termination may interrupt queued logical purges, while account guards still prevent cross-account reads. Corrupt/missing caches require online refresh. Web stays online-only until SQLite WASM deployment. No offline editing, queued mutations, automatic merging, background download guarantee or cross-device offline synchronization is included. Required charts must previously load online; visiting only the Setlists list may not cache arrangements.

`test/offline_rehearsal_test.dart` uses production repositories/providers with a simulated Firebase transport to cover complete/incomplete caches, published/draft separation, verified UID profile restoration, cold offline resume and last song, local chart operations, reconnection/disconnection, stale refreshes, deletion, account switching and permission revocation. No Firestore schema/rules/index changes, dependencies or deployment are required.


## Rehearsal metronome (Phase 4)

The icon beside Chart Settings toggles local metronome playback using the selected exact arrangement's BPM and meter. BPM must be 1–400; supported meters are 3/4, 4/4, 6/8 and 8/8. **BPM means quarter notes for /4 and eighth notes for /8**: every bar has respectively 3, 4, 6 or 8 evenly spaced ticks, with only the first tick accented. There are no secondary accents, tempo controls or inferred defaults. Missing/unsupported metadata shows brief feedback.

`rehearsal/services/rehearsal_metronome.dart` wraps the native metronome audio engine, serializes start/stop requests and cancels delayed starts. Beat scheduling runs outside Flutter rebuilds with tick callbacks disabled. Two original synthesized 20 ms mono 44.1 kHz ticks are bundled in `assets/audio/` (raw PCM16 for Android/Windows, WAV copies for Apple). No network audio, background service or saved metronome state is used. Song/arrangement changes, page navigation, disposal and app backgrounding stop playback; it never restarts automatically. A route observer preserves this behavior when Chart Settings or editors cover Rehearsal.

The native adapter targets Android, iOS, macOS and Windows; Web/Linux report unavailable audio. Native hardware latency and audible tick quality require device verification. Unit/widget tests verify configuration, bundled audio handoff, cancellation, button state, missing BPM and navigation stops; they do not measure physical audio timing.


## V1 finalization audit (2026-11-02)

See [audit](v1-final/audit.md), [test results](v1-final/test-results.md), [security review](v1-final/security-review.md), [release checklist](v1-final/release-checklist.md) and [V1 status](v1-final/v1-status.md). Local evidence: clean analyzer, 252-test full Flutter suite, 16 final targeted Rehearsal/metronome tests, 27 Firestore emulator tests and successful Android debug APK. Production Console/rules, real OAuth, audible timing and device offline/restore behavior are not certified.

Metronome controllers now share an engine operation queue with playback ownership: late cleanup/disposal from an old Rehearsal cannot stop a new view's playback. Android's legacy and Android 12+ cloud/device-transfer policies exclude `app_flutter/`, the Drift documents directory holding charts and cached access/profile metadata. Account-scoped SharedPreferences behavior remains unchanged. This prevents inclusion in new supported backups; it does not erase old backups or encrypt SQLite.

Android release signing now loads ignored `android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`); missing keys fail the release task instead of falling back to debug signing. No key file is present, so the release build is blocked. Application ID remains `com.example.worship_flow`, matching the local Firebase JSON, which currently contains Android and Web OAuth clients. Owner identity/certificate/provider/deployed-rules checks remain manual; no deployment occurred.

Limitations clarified by the audit: arrangement CRUD/Firestore still allow only 3/4, 4/4 and 6/8, despite the metronome accepting 8/8 internally; Inter has no bundled assets and may require font-cache/network access; eight large arrangement sources can exceed Firestore's aggregate 1 MiB Song document limit. Tested SDK is Flutter 3.44.6/Dart 3.12.2; the declared older minimum is not certified. No deferred features or new dependencies were introduced. Release assessment is **NOT READY** pending release signing and required verification.


### Android metronome reply fix

The installed metronome 2.0.13 Android plugin omits MethodChannel replies for void operations. Awaiting `init` therefore prevented reaching `play`; awaiting teardown could also stall the shared operation queue. `MainActivity.configureFlutterEngine` now delegates to the existing registered plugin and acknowledges those operations, returning native exceptions as platform errors. This is a compatibility shim for 2.0.13; review/remove it when upgrading that plugin. No second plugin/audio engine is created.

The Android adapter uses the same channel directly to preserve initialization/playback errors instead of the package wrapper swallowing them, with a five-second reply timeout. The button turns ON only after native `isPlaying` confirms playback; failures remain neutral, show the existing snackbar and log debug diagnostics. The shared ownership/serialization/cancellation guards remain in place. Playback uses 75% engine gain, with a higher-amplitude high accent asset; device media volume remains user-controlled. Other platform adapters and BPM/meter conventions are unchanged.

Validation: 20 targeted metronome/Rehearsal tests, including missing replies, propagated platform errors, delayed initialization, visible failure/retry and stronger accent samples. An Android emulator native smoke check confirmed ON then native OFF for 3, 4, 6 and 8 beats. Actual speaker/headphone audibility, accent perception, hardware timing and signed-release playback still need physical-device verification. Native changes require a full rebuild/reinstall, not hot reload. No Firebase or persistence changes.
