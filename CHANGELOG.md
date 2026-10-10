# Changelog

## 0.3.9 — release candidate (build 16)

- Low battery is a yellow warning showing the actual charge percentage instead of a red Error state.
- Explains that on battery the mode requires more than 10% charge; connecting power remains supported.
- The helper sends a typed battery refusal; real helper/restoration failures remain errors. The 10% safety cutoff is unchanged.

## 0.3.8 — release candidate (build 15)

- Build 15: fixed a first-launch crash (`EXC_BREAKPOINT` in the XPC client). XPC error and invalidation callbacks no longer inherit main-actor isolation; NSXPC calls them on its own queue. Regression test uses a real connection to a missing Mach service.

- New wordmark: the owner-approved graffiti marker lettering (variant 4), vectorised from the approved artwork into outlines in the source; no font files.
- The final lowercase «d» and the «p» are separate outlines; the «d» turns about the centre of its oval, falls and lands as «p» — «Shut Your Lip». Reduce Motion cross-fades d → p without turning.
- White marker letters with a thin black outline stay readable on light and dark desktops.
- Unchanged: transparent frameless splash, 1.5× lips, kiss, travelling zipper pull, flight into the real menu bar icon, one animation per launch/reopen, automatic language.

## 0.3.7 — release candidate

- Kiss and zipper animation on every launch, with the playful Lid → Lip wordmark and a first-launch guide to the real menu bar icon.
- Build 12: duplicate launch/reopen events no longer skip the animation.
- Build 13: lips enlarged 1.5×; transparent splash with no card, border or rectangular shadow, including Reduce Motion.
- Automatic Russian/English language, accessible onboarding and reduced motion.
- Smooth native duration slider; edit an active session without switching it off.
- Restore ordinary sleep before handled helper termination, with confirmed success.
- Recover from corrupt existing state; preserve failures for retry.
- Show lost helper communication as unconfirmed state instead of Off.
- Universal Apple Silicon and Intel packaging.

Apple notarization and hardware/test-system acceptance remain release gates.
