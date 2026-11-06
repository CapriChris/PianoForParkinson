# 0.1.64+65 account release integration

- First parent: teammate main `ebb7e3f` (0.1.63+64); second parent: local account implementation `d966341`. Both histories are retained.
- The active implementation remains AccountController + AccountApi + AccountSessionVault. The teammate account UI, launcher branding, registration/password flows, plan reminders and all existing tests are retained. The older AccountApplication/AccountSession controller/AccountVault implementation is not introduced.
- Existing 0.1.63 queued ciphertext is migrated only from a validated current-account metadata row (user/patient/server/profile, account directory hash and capture UUID). The native helper moves only that one legacy directory, refuses overwrite/path escape, and leaves all unclaimed legacy data untouched.
- Added account-specific encrypted CaptureVault namespaces and tracked asynchronous capture shutdown. Account shutdown awaits cloud sync, capture operations, practice writes and assistant conversation closure before releasing its database ownership. A partially initialized repository is closed as well.
- Added encrypted, atomic refresh-token revocation compensation in the existing Android Keystore vault. Logout invalidates local access immediately and awaits a bounded server acknowledgment; offline failures and refresh replies arriving after logout are retained for retry. Patient UUID drift during refresh fails closed.
- The teammate OS file lease remains the single global foreground/headless owner. Both execution paths continue using the existing AutoSync implementation; no background camera or recording initialization is added.
- Registration preserves the teammate visual design and asks for an explicit automatic-sync confirmation dialog before sending the registration request. Dismissal/cancellation sends no registration request; video and AI authorization remain separate.
- Version increases from 0.1.63+64 to 0.1.64+65. Default API remains `https://ccqspace.site/pd-rehab/api`; the retained build override is `PD_API_BASE`.

## Validation on 2026-11-07

- Flutter 3.47.7: `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub --reporter expanded`: 783 passed, 2 opt-in live tests skipped.
- Isolated local HTTPS account integration via `scripts/run_local_sync_smoke.ps1`: passed. Covers two real registered accounts, cross-account rejection, plan progress 1/2 then 2/2, repeat sync uploads zero, remembered login rotation, awaited logout makes the old access token return 401, and password recovery/change.
- `scripts/test_capture_namespace.ps1`: standalone JVM regression uses the exact native migration helper on real temporary files; verifies original encrypted bytes, successful AES-GCM decryption after move, idempotence, unrelated legacy preservation, invalid scope/ID rejection and occupied-target preservation. Real SQLite/channel tests verify only matching account metadata can request migration, before retention deletion.
- Historical implementation reports in `docs/account_registration_*` describe the earlier local branch and are retained as historical evidence; this file describes the merged release.
- Final ARM64 Debug APK built successfully (0.1.64+65), APK v2 signature verified, package `com.pianoforparkinson.piano_practice.validation`. File size 689,188,447 bytes; SHA-256 `b98ba8d3aa9968dcb19b14e582fe5a010a94c06b9f19db05f6bcdbbce40a91cd`. The functional source is `cffa29c`; later documentation commits do not change the binary.
- Existing staff HTTPS sync smoke was also run against a separate local backend and passed. The two default-skipped opt-in tests were therefore both executed separately.
- The production backend has been deployed with migration n0c2d4e6f8a0. Physical-device camera, Keystore restart persistence and actual WorkManager/vendor scheduling are not claimed as verified here.
