# Shut Your Lid 0.3.7 — signed release candidate

A small menu bar app that keeps your MacBook working with its lid closed, for a duration you choose.

## New

- Borderless transparent launch animation with lips enlarged 1.5×: a kiss, a closing zipper and the playful Lid → Lip wordmark, followed by a transition into the menu bar.
- A compact native menu and settings, with a smooth custom duration slider and live changes to an active timer.
- Russian and English selected automatically from macOS.
- Restore ordinary sleep when the helper handles termination or discovers corrupt recovery state; show lost communication as unconfirmed state.
- Developer ID signature and a launch constraint that rejects a helper with the wrong signing identity.
- Universal binaries for Apple Silicon and Intel, macOS 14+.

## Install

Open the DMG, drag Shut Your Lid to Applications, and launch it. Approve its background helper in macOS Login Items & Extensions on first enable. Each Mac stores its state locally. No publisher key or account is included.

## Candidate limits

This is not yet a stable public release. Apple notarization is blocked by a developer agreement, and clean-system helper/upgrade tests and hardware acceptance remain pending. Do not bypass Gatekeeper. Never put a working MacBook in a bag.

## Files

The release folder contains the signed DMG, app ZIP, source-only ZIP and SHA256SUMS. Publish only after the release gate in docs/RELEASE.md is satisfied.
