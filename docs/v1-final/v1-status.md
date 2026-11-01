# V1 status

Verified local implementation: Firebase Google authentication/profile/group and invitation/member foundations; group-authorized Firestore Song/Arrangement and Setlist persistence; explicit draft/publish/conflict recovery; advanced ChordPro source editing and preview; chart transforms/compact rendering/section navigation; offline read-only Rehearsal; UID-scoped resume/preferences; local metronome.

This pass fixed the metronome cross-route cleanup race, excluded protected Android cache from backups/transfer, and replaced debug release signing with explicit keystore configuration and a fail-fast guard. Canonical source and Firestore schema/rules were preserved.

Evidence: clean analyzer, 252-test full Flutter suite, 16 final targeted tests, 27 Firestore emulator tests, successful Android debug build and packaged backup-policy checks. Release build is blocked by absent release signing credentials. Interactive device/audio/airplane-mode, real OAuth, deployed-rules and signed-release verification are outstanding. See the other reports for commands and gates.

Remaining nonblocking limitations include the 8/8 CRUD gap, unbundled Google Fonts, aggregate Firestore document-size limits, unencrypted device cache/unknown offline revocation and unverified non-Android releases. Deferred scope stays deferred: offline editing/queues/merge, import/export, history, backend functions/paid services and additional performance modes.

A successful debug build and simulated/emulator tests are insufficient approval to distribute. Complete the signing blocker, then the manual release checklist and signed-build checks before reconsidering.

**NOT READY** — release signing is not provisioned and required release verification is incomplete.
