# Shut Your Lid 0.3.8 — signed release candidate

A small menu bar app that keeps your MacBook working with its lid closed, for a duration you choose.

## New in 0.3.8

- Build 15 fixes a first-launch crash when the XPC helper connection fails. Background error and invalidation callbacks no longer inherit MainActor isolation; real NSXPC regression tests pass in debug and release.

- The launch animation uses the approved graffiti marker lettering. «Shut Your Lid» is drawn from outlines vectorised from the approved artwork; no font files are bundled.
- The last «d» turns about the centre of its oval, falls and lands as a separate «p»: «Shut Your Lip». With Reduce Motion it cross-fades instead.
- Letters keep a thin black outline, so the transparent splash reads on light and dark desktops.

The other features from 0.3.7 remain: transparent frameless splash with 1.5× lips, kiss, travelling zipper pull, flight into the menu bar icon, native menu and settings, live duration changes, automatic Russian/English, helper safety fixes and the launch constraint.

## Install

Open the DMG, drag Shut Your Lid to Applications, and launch it. Approve its background helper in macOS Login Items & Extensions on first enable. Each Mac stores its state locally. No publisher key or account is included.

## Candidate limits

The exact app has been accepted by Apple notarization and stapled, and local Gatekeeper assessment passed. This is not yet a stable public release: clean-system helper/upgrade tests and hardware acceptance remain release gates (see docs/RELEASE.md). Do not bypass Gatekeeper. Never put a working MacBook in a bag.

## Files

The release folder contains the signed DMG, app ZIP, source-only ZIP and SHA256SUMS. Publish only after the release gate in docs/RELEASE.md is satisfied.
