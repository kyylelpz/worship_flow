# Android V1 release checklist

Do not deploy or publish until these gates are completed by the owner.

## Signing / identity — Blocker

- [ ] Confirm ownership/availability of `com.example.worship_flow`, or coordinate a permanent package change with Firebase/OAuth first. Keep current identity for existing installations until a migration decision is made.
- [ ] Provision a protected upload/release keystore. Create ignored `android/key.properties` containing `storeFile` (absolute path recommended), `storePassword`, `keyAlias`, `keyPassword`. Never commit or print these values. The release guard deliberately rejects missing configuration.
- [ ] Choose release version/build number; current declaration is `0.1.0` (no explicit `+build`). Use a monotonically increasing build number for published updates.
- [ ] Run `flutter build apk --release` and, for Play distribution, `flutter build appbundle --release`; verify signing certificate and install the intended artifact. No temporary/debug key qualifies for release approval.

## Firebase / authorization — manual gates

- [ ] Verify Google provider enabled, correct support email, registered package and SHA-1/SHA-256 for release certificate and Play App Signing certificate where applicable. Local JSON currently has matching package plus Android and Web OAuth clients; this does not prove Console configuration or certificate registration.
- [ ] Verify production `(default)` Firestore rules/indexes match the reviewed files. If deployment is needed, owner runs `firebase deploy --only firestore:rules,firestore:indexes --project worship-flow-f3166`. No new deployment is required solely for this audit's code fixes.
- [ ] Smoke-test Administrator/Leader/Trainee on separate real accounts: group reads, denied trainee mutations, invitation opt-out/accept/decline, member changes, last-Administrator protection and cross-group denial.
- [ ] Review opt-in email-discovery privacy, Spark quotas and operational ownership. App Check/rate limiting are not claimed protections.

## Device verification — required before release

- [ ] Real Google sign-in/cancellation/sign-out/account switching; profile gate, loading/error retry and force-close restart/resume.
- [ ] Two-device concurrent Song/Arrangement/Setlist edits, deletion conflicts and retained local drafts; nested Song editing must preserve parent Setlist edits.
- [ ] Cache a complete published setlist, enable airplane mode, force-stop/restart, resume last song; check missing/partial cache messages, font fallback and read-only controls. Reconnect, revoke membership and switch accounts; confirm protected content disappears appropriately.
- [ ] Metronome ON/OFF, first-only accent, correct 3/4/4/4/6/8 BPM convention, rapid taps/swipes, pushed screens, Android Back, background/foreground and sustained playback without lingering audio. 8/8 audio is supported internally but cannot currently be saved by arrangement CRUD/rules.
- [ ] Chart/preview typography, Standard/Nashville, transposition, grids/repeats/blank lines and section bubbles on narrow/landscape/large-text devices.
- [ ] Verify Android cloud backup/device transfer does not restore protected chart/access cache. Confirm release manifest/debug flags, permissions and logs. Test upgrade from an existing installation using the real release identity.

Other platforms are not release-certified by this audit. Web offline cache and Web/Linux metronome remain unavailable; Windows native Google authentication is unsupported. No invitations-by-email delivery, offline writes/merging, import/export, revision history or additional player mode is required for V1.

Signing reference: [Flutter Android release guidance](https://docs.flutter.dev/deployment/android).
