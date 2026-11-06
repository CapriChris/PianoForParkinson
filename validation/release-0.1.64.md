# 0.1.64+65 account release integration

- First parent: teammate main `ebb7e3f` (0.1.63+64); second parent: local account implementation `d966341`. Both histories are retained.
- The active implementation remains AccountController + AccountApi + AccountSessionVault. The teammate account UI, launcher branding, registration/password flows, plan reminders and all existing tests are retained. The older AccountApplication/AccountSession controller/AccountVault implementation is not introduced.
- Added account-specific encrypted CaptureVault namespaces and tracked asynchronous capture shutdown. Account shutdown awaits cloud sync, capture operations, practice writes and assistant conversation closure before releasing its database ownership. A partially initialized repository is closed as well.
- Added encrypted, atomic refresh-token revocation compensation in the existing Android Keystore vault. Logout invalidates local access immediately and awaits a bounded server acknowledgment; offline failures and refresh replies arriving after logout are retained for retry. Patient UUID drift during refresh fails closed.
- The teammate OS file lease remains the single global foreground/headless owner. Both execution paths continue using the existing AutoSync implementation; no background camera or recording initialization is added.
- Version increases from 0.1.63+64 to 0.1.64+65. Default API remains `https://ccqspace.site/pd-rehab/api`; the retained build override is `PD_API_BASE`.

## Validation on 2026-11-07

- Flutter 3.47.7: `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub --reporter expanded`: 781 passed, 2 opt-in live tests skipped.
- Isolated local HTTPS account integration via `scripts/run_local_sync_smoke.ps1`: passed. Covers two real registered accounts, cross-account rejection, plan progress 1/2 then 2/2, repeat sync uploads zero, remembered login rotation, awaited logout makes the old access token return 401, and password recovery/change.
- Historical implementation reports in `docs/account_registration_*` describe the earlier local branch and are retained as historical evidence; this file describes the merged release.
- APK compilation is handled separately by the release coordinator. Physical-device camera, Keystore restart persistence and actual WorkManager/vendor scheduling are not claimed as verified here.
