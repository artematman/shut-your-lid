# Security remediation — 0.3.7 candidate

The privileged power helper accepts fixed operations from the expected signed application, and the app requires the expected signed helper. A launchd SpawnConstraint restricts executable identity, Team ID and Developer ID validation category. Each Mac stores its own root-owned recovery state.

Resolved paths include unknown telemetry, the 10% battery boundary, monotonic timer expiry, failed restoration retry, corrupt existing state recovery, handled helper termination and unconfirmed heartbeat failure. Duration updates preserve the recovery record and apply only to an active lease.

There are no external package dependencies, runtime network clients, Keychain-reading APIs, analytics or document collection in the reviewed code. Private signing keys and notarization credentials are not exported.

No sandbox or absolute-safety guarantee is claimed. Final artifact checks, clean-system SMAppService/constraint/upgrade testing, physical lid and power acceptance and Apple notarization are distinct release gates. Synchronous system command execution has no explicit timeout; this remains a robustness limitation. SIGKILL cannot run a termination handler; recovery depends on the helper restarting with its persisted record.

The release source export excludes private Git history, local audit workspaces, credentials and old builds. Downloaded artifacts must pass signature, privacy and Gatekeeper checks.
