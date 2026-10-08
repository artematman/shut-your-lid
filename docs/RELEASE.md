# Release 0.3.8

The release script builds a Developer ID signed universal app for macOS 14+.
Recipients drag the app into Applications and approve their own SMAppService background item on first enable. No build credentials are distributed.

## Apple notarization

Use an existing local notarytool Keychain profile. Never commit or paste its password, API key, private key or exported signing identity. Keep credentials out of CI logs.

1. Build the signed app and ZIP it with ditto.
2. Submit the ZIP with `xcrun notarytool submit <zip> --keychain-profile <profile-name> --wait`.
3. After Accepted, staple and validate the app with `xcrun stapler staple <app>` and `xcrun stapler validate <app>`.
4. Rebuild the ZIP and disk image from the stapled app; sign the disk image, notarize and staple it too.
5. Verify a clean download on another Mac with Gatekeeper enabled, and rerun artifact checks. Do not bypass Gatekeeper.
6. Generate SHA-256 checksums only after all stapling and packaging is complete.

## Public release gate

- Final source and packaged app privacy scan; no private keys, credential files, developer paths or audit workspaces in downloads.
- Both executables contain arm64 and x86_64; signatures and helper identity verified.
- Launch/spawn constraints verified against actual code signatures; separate test-system helper replacement and denied-client tests.
- SIGTERM delivery through launchd on a test system; corrupted recovery with success and failure; heartbeat disconnect.
- Physical closed-lid continuity, restoration, battery and thermal behavior on supported setups. A test runner cannot establish real lid closure.
- Apple notarization Accepted and stapling validation.
- Source snapshot uses clean public provenance with no old personal email history. For this publication the complete existing Git history was scanned and contains only public source and noreply commit identities. Any future private history must be independently audited or excluded by using a clean source-only export.

GitHub release notes must report the actual validation and remaining limits. A signed local candidate is not a notarized stable release.
