# Security and privacy changes in 0.2.0

The application is a local macOS utility. Each copy talks to a daemon on the same Mac through a local Mach service. There is no account system, remote endpoint, analytics SDK, document collection or runtime Keychain-reading code. Its XPC interface carries only fixed power operations and bounded duration/battery parameters, never file paths, shell commands or credentials. Both endpoints require the expected signing identity. These are reviewed design properties, not a claim of an OS sandbox or perfect protection against every vulnerability.

## Resolved in this version

- Missing or invalid power-source data no longer defaults to AC. An internal battery with unknown charge blocks enabling while on battery and stops a running mode. Peripheral/UPS readings cannot replace the internal battery.
- On battery at 10% or lower, the daemon restores normal sleep and requests immediate sleep, even if the lid is open. Known AC does not trigger this battery stop. Normal guard detection is every ten seconds.
- A failed restore keeps both the recovery record and the intent to sleep. A failed sleep command is reported and retried, and a new enable is blocked while recovery is unresolved.
- Duration and the 90-second heartbeat lease use continuous monotonic time. Changing the calendar clock cannot extend either. Expiry dates displayed in the menu reflect the remaining monotonic duration.
- The release pipeline remaps source paths, strips debug symbol references before signing, and scans both executable files and final app resources for personal paths and common secret patterns.
- The repository uses a GitHub noreply identity. Published branch history is checked for personal author/committer addresses. A credential-free source ZIP is prepared without any Git metadata.

## Signing keys and user data

The developer's private signing key stays in the build machine's Keychain. `codesign` uses that key while producing the release; it is not copied into source code, the application or the ZIP. A recipient gets the public code signature/certificate, which identifies the publisher and does not grant access to the publisher's Mac or Keychain.

The runtime application does not invoke Keychain APIs or upload files. It reads its own duration preference and embedded service metadata. The root daemon reads and writes only its own recovery state and executes fixed system power commands. A third-party client cannot ask it to read a password, document or arbitrary file through this interface.

The privileged daemon has root authority, so it must remain small and receive continued review. `privacy-gate.py` provides regression checks for known secret formats, personal paths and selected forbidden APIs; it is not a complete static analyzer or a sandbox. Public name and Team ID in the certificate are intentional publisher metadata, not secret keys.

## Before public distribution

Keep the existing repository private. Rewriting a branch removes email from that branch's published history, but GitHub may retain old objects or cached commit pages. For public release, import the verified source-only export into a fresh repository/history rather than relying on remote garbage collection. The source ZIP contains neither `.git` nor private audit/maintenance files. The old history backup is kept outside the repository and release artifacts for recovery only.

Notarization and stapling, actual negative XPC transport tests, real lid closure with task continuity, and failure recovery on hardware remain release requirements. The current build is signed but is not a notarized public release. No signing/notarization passwords or private keys should be committed, pasted into chat or added to build logs. A local Keychain profile can supply notarization credentials when the owner configures it.

System command execution still depends on macOS responsiveness; `pmset`, `pgrep` and `launchctl` do not yet have explicit per-command timeouts. This is a remaining robustness limitation, not a demonstrated secret-exfiltration path.
