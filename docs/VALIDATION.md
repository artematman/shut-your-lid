# Local validation — 2026-10-06

- Source: Island Pro commit `2d03a54`, branch `audit/beta2-fixes`; original checkout remains clean.
- New standalone package: 25 tests in six suites passed, including actual AppKit panel sizing, two-display geometry, permission/refusal state, migration preflight, lease boundary, battery/thermal/time guards, disconnect restoration, crash recovery, corrupt records and retry after failed restoration.
- Release build completed with Swift 6.3.3 for arm64.
- Installed `/Applications/Shut Your Lid.app` version 0.1.0 and its own helper passed Developer ID identifier/team requirements and strict/deep signature verification.
- The ZIP was separately extracted to a local temporary folder and passed the same artifact verification. Ship the ZIP rather than an app directory in a File Provider folder: that folder adds Finder metadata that interferes with signature verification.
- Private GitHub repository created and initial source pushed: `artematman/shut-your-lid`.
- The new app process is running. Its helper has not been approved or activated by this work.
- The old Island Pro daemon was registered/running and `pmset -g` reported `SleepDisabled 1`. No power settings, old permissions, TCC entries or old state files were changed.
- The owner-operated continuity recorder correctly refused to start while the old daemon remained registered.

## Pending owner acceptance

- Computer Use timed out reading the accessory app and SystemUIServer; live menu interaction, Escape/outside dismissal and the physical display position have not been independently verified. Geometry and content sizing were exercised in tests.
- Disable the old mode, quit Island Pro and disable its background helper through macOS settings; approve Shut Your Lid's distinct helper through the normal macOS prompt.
- Confirm the switch reflects an actual active mode, then record a real background task over at least two minutes of physical lid closure using `Scripts/lid-check.py` and owner-confirmed close/open times.
- Confirm switch-off restores normal sleep. Repeat on the intended power/display setup.
- Remove the old Island Pro feature only after successful acceptance, as a separate change.

Tests and signatures establish software/artifact checks, not hardware operation with the lid closed. This build has not been notarized for public distribution.
