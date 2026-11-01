# V1 audit — 2026-11-02

Scope: Android V1; local source/configuration review, Flutter tests, Firestore emulator and Android builds. No deployment or production-resource changes. Deferred features are not defects.

| ID | Severity | Finding / evidence | Resolution |
| --- | --- | --- | --- |
| B1 | Blocker | Release used debug signing; no `android/key.properties` exists. | Removed fallback, added explicit release-key configuration and fail-fast guard. Owner must supply signing credentials; release verification remains blocked. |
| H1 | High | Separate Rehearsal controllers shared one native audio engine but had independent queues. Reproduction: delayed departing initialization/cleanup stopped the arriving player (`playing` expected 1, actual 0). | Shared queue per audio engine, explicit playback ownership; old-route disposal cannot release the new owner. Two regressions plus existing lifecycle tests pass. |
| H2 | High | Protected SQLite charts and cached access/profile metadata lived in Android app documents without backup exclusions. App sandboxing alone did not exclude OS backup/transfer. | Added legacy backup and Android 12+ cloud/device-transfer exclusions for `app_flutter/`, where Drift stores the database and journals. UID-scoped SharedPreferences remain unaffected. Source XML and debug APK packaging checked; physical restore behavior unverified. |
| M1 | Medium | Application ID remains `com.example.worship_flow`; local Firebase package matches it. | Owner must confirm final identity before distribution. Renaming requires coordinated Firebase/OAuth registration; no speculative rename. |
| M2 | Medium | Metronome accepts 8/8, but Song validation and Firestore arrangement rules permit only 3/4, 4/4, 6/8. | Existing limitation documented. 8/8 playback configuration is tested, but ordinary production CRUD cannot save an 8/8 arrangement. Not silently expanded in this stabilization pass. |
| M3 | Medium | Inter is loaded through Google Fonts; no font assets are bundled. | Offline chart data is local, but first font loading is not guaranteed offline. Device checks must cover cached-font and unavailable-font startup; fallback typography may differ. |
| M4 | Medium | Up to eight 200,000-character arrangement sources share one Song document. | Aggregate payload may exceed Firestore's 1 MiB document limit before individual field limits. Save errors retain drafts; reduce source size/arrangement count. No schema redesign. |
| L1 | Low | Declared minimum Flutter 3.22 is older than APIs in use. Build warns about Firebase plugins using KGP. | Verified with Flutter 3.44.6/Dart 3.12.2; lower SDKs and future Flutter upgrades are not certified. No dependency upgrades. |

No additional high-priority authorization bypass or data-loss regression was confirmed in the inspected paths/tests. Existing transaction revisions, expected Song/Arrangement comparisons, draft isolation and reference guards remain intact. This is bounded evidence, not a formal proof or a completed production penetration test.

Changed implementation: Android Gradle signing configuration, manifest plus two backup XML resources, metronome service and its regression tests. Firestore schema/rules, canonical ChordPro, preferences and content repositories were not changed.
