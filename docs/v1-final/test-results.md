# V1 verification — 2026-11-02

Environment: Windows, Flutter 3.44.6 stable / Dart 3.12.2. Results are local; no production writes or deployment.

| Command/check | Result |
| --- | --- |
| `flutter analyze --no-pub` (final code) | PASS, no issues. |
| `flutter test --no-pub` | PASS, 252 tests, full suite run once after initial fixes. |
| `flutter test --no-pub test/metronome_test.dart test/rehearsal_test.dart` | PASS, 16 tests after final playback-ownership guard and second regression were added. The full suite was not redundantly rerun afterward. |
| `firebase emulators:exec --only firestore --project demo-worship-flow "npm --prefix firestore_tests test"` | PASS, 27 tests, zero failures/skips. Rules unchanged after execution. Expected PERMISSION_DENIED diagnostics belong to denial assertions. |
| `flutter build apk --debug --no-pub` | PASS; debug APK built. Firebase plugin KGP migration warning remains. |
| `flutter build apk --release --no-pub` | BLOCKED, exit 1: explicit missing-release-signing guard. Not a successful release compilation/signing/R8 verification. |
| Python `xml.etree.ElementTree` + `zipfile` check | PASS: manifest points to both backup policies; legacy/cloud/device-transfer exclude `app_flutter/`; policies and PCM ticks are packaged in debug APK. |
| `git diff --check` | PASS. |

The metronome race was reproduced first with a failing focused test; the fixed queue and ownership tests then passed. Existing tests cover Auth error redaction/restoration, roles/invitations, group queries and forbidden writes, Song/Arrangement CRUD/conflicts, Setlist drafts/publishing/references, parent-editor navigation, engine/renderer/preview, section tracking, SQLite corruption/isolation, offline cold starts/reconnection/revocation, resume and preferences. Most Flutter backend checks use simulated transports; emulator tests exercise actual rules separately.

Not performed: interactive device UI/audio tests, actual Google sign-in/account switching, production Console/OAuth/deployed-rules inspection, real airplane-mode/restart/backup-restore tests, release-signed install, Play upload, iOS/macOS/Windows/Web release builds, hardware timing/latency or sustained-memory benchmarks. A connected Android device was discoverable in the preceding phase; no claim of manual verification is made here.
