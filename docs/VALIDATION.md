# Validation — 0.3.9 build 17 candidate, 2026-10-10

- 93 tests in 14 suites passed, including typed battery/heat warnings, clearing after cooling, wire compatibility and failure precedence.
- Native dark-mode battery and heat warning previews were rendered and inspected.
- Source and signed app/archive privacy regression checks passed. This is a scoped regression check, not a new independent full audit.
- App notarization Accepted (`33e6d052-79d5-46d5-a7f8-7858eb50eb2f`); DMG Accepted (`91126cd6-0a57-47c4-94f8-84f7bc53f4d0`); tickets stapled, local Gatekeeper assessment passed.
- On the developer Mac, two live readings reported thermalState fair; the serious/critical refusal threshold is unchanged. No temperature in degrees was obtained.
- Clean-system helper upgrade, physical lid/battery/thermal and recovery acceptance remain pending. This remains a prerelease.

## Previous baseline

# Validation — 0.3.8 build 15 candidate, 2026-10-08

## Completed

- Independent final build 15 run: 89 tests in 14 suites passed. The real NSXPC missing-service regression reproduces the build 14 crash and passes after moving background error/invalidation callbacks out of MainActor isolation. The same 2 regression tests passed in an optimized release build. No helper authorization or power policy was relaxed.
- Native artwork previews passed separately (2 tests). Approved option 4 graffiti outlines animate the separate d into p; no font files are distributed.
- Installed build 15 passed launch and two Dock reopen smoke checks: the same process stayed running, no new app crash report appeared, and ordinary sleep remained enabled (SleepDisabled 0). This does not establish physical lid or helper upgrade behavior.
- Final signed DMG: Apple notarization Accepted (`7be88d4c-6947-439f-9443-12b7a705f8fd`), stapled and locally assessed by Gatekeeper.
- Exact build 15 app: Apple notarization Accepted (`be91f176-cb03-49e7-a1d3-f708f007c645`), stapled; local Gatekeeper assessment passed.
- Final source, Git history and package privacy checks passed. No confirmed open vulnerability was found in the reviewed scope; hardware and clean-system checks below are still required.

- Final independent Codex run (build 13): 87 tests in 13 suites passed, including returning-user launch, duplicate reopen and a subsequent fresh splash, and transparency of the artwork while retaining its outline, mouth, teeth and pull. View rendering was verified separately (2 preview tests); running heavy image generation concurrently with timer assertions can delay MainActor and invalidate wall-clock test bounds.
- Claude inspected fixed-operation XPC, restoration races, onboarding locality and secret handling; no confirmed open vulnerability was found in the reviewed code. This is not an absolute security guarantee.
- `SpawnConstraint` restricts launchd to the expected Developer ID helper. Claude tested the same constraint with temporary user agents: the signed helper copy started and exited safely as non-root; a foreign binary and an ad hoc signed replacement were rejected. Test agents were removed.
- Both app and helper compiled as universal arm64/x86_64 binaries; Developer ID signatures and packaged launch constraint checks passed on the staging candidate.
- The installed old app was quit normally, and the system reported SleepDisabled 0 afterwards.

## Not established by these checks

- Actual final launchd/SMAppService registration and replacement rejection on clean macOS 14+, including upgrade behavior for an existing background registration.
- Physical closed-lid continuity, battery 10%, serious thermal state, background-item removal, crash and reboot recovery. These need a separate test machine or owner-operated hardware acceptance.
- Dock animation is implemented and compiled in the final candidate; first-run and reopen UI checks are recorded after installation. Multi-display and physical smoothness acceptance remain limited to the tested setup.
- Gatekeeper assessment on a separate, clean Mac after downloading the final package remains pending. Local notarization and assessment have passed.

The repository and downloads must describe the build as a signed release candidate until these gates are satisfied.
