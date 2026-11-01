# V1 security review

Local rules and repository audit used the Firebase security-rules-auditor skill. The 27 emulator security tests pass. No production rules were read or deployed, and no Firestore rules/schema changes were necessary.

- **Identity and authority:** Rules require authenticated, email-verified Google identity. Group content reads require actual membership in that exact group; content writes require its Administrator/Worship Leader role. Global profile roles/client claims do not elevate access. Trainees retain reads and charts, with management UI and writes guarded.
- **Profiles/discovery:** Private profile gets are owner-only; email discovery is exact-document lookup with current group-Administrator authorization, never directory listing. Opt-out prevents new invitations. Invitation acceptance atomically validates the immutable assignment, member/index and acceptance notification; member mutations retain a surviving Administrator witness.
- **Integrity:** Setlist revisions increment in transactions. Editors retain rejected drafts rather than overwriting newer content. Song/Arrangement expected-value checks protect app edits; Firestore rules enforce authorization/shapes, not the editor's expected baseline. Catalog registrations protect referenced deletions, including published and draft references. Privileged writers intentionally remain able to edit group content.
- **Offline protection:** UID/group scope, leases and generation checks reject account-switch/revocation races; incomplete bundles cannot claim full offline availability. Server denial is not a network fallback. Logout/revocation logically purge protected content. Android backup/transfer now excludes the Drift app-documents directory; SharedPreferences retain UID-scoped settings/navigation.
- **Build/logging:** Release builds ignore mock/emulator compile flags. Auth diagnostics are debug-only and redact credentials/tokens; Firebase client config/OAuth IDs are public identifiers, not server credentials. No private signing key or service-account credential was introduced. Release artifacts cannot silently use debug signing.

Residual **Medium** risks: offline revocation is unknowable until revalidation; SQLite is unencrypted and logical deletion is not forensic erasure; rooted devices/OS extraction remain outside these guards. Existing backups are not retroactively erased by the new policy. Apple backup behavior was not verified. Exact email guessing can reveal opt-in registration to authorized Administrators; no server rate limiting or App Check enforcement is claimed. Rules cap individual fields/items, but catalog usage lists and aggregate Song size still meet Firestore document/quota limits. Trusted service-account/server access bypasses client rules and needs separate IAM controls.

Audit rubric (bounded local assessment):

```json
{"score":4,"summary":"No confirmed privilege escalation in inspected rules; emulator matrix passes. Deployment and device privacy gates remain.","findings":[{"check":"Storage and privacy","severity":"minor","issue":"Offline SQLite is sandboxed but unencrypted; email discovery is guessable by authorized administrators.","recommendation":"Accept/document these V1 tradeoffs; verify device and deployed-rule behavior before distribution."}]}
```

References: [Firestore rules conditions and access-call limits](https://firebase.google.com/docs/firestore/security/rules-conditions), [Android backup/transfer policies](https://developer.android.com/identity/data/autobackup). This review does not certify production configuration or defeat compromised devices.
