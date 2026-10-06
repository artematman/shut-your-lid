# Shut Your Lid

Standalone macOS menu bar utility for keeping a MacBook working with its lid closed. Version 0.2.0, macOS 14+, current build arm64. Hardware acceptance is pending; this is a signed local preview, not a notarized public release.

Click the laptop icon for the compact switch «Работать с закрытой крышкой». The panel fits its content, anchors to the icon on its display, and closes with Escape or an outside click. Choose 30 minutes, 1, 2, 4, 8 or 12 hours, or enter a custom duration from 1 to 720 minutes. The last choice is saved locally; four hours is the initial default. A running duration is fixed: switch off before selecting a new duration. The switch becomes on only after the helper confirms the actual sleep-disabled flag. Quit is available in the panel and ends the lease.

## Start and migrate

1. Turn off closed-lid mode in Island Pro. Quit Island Pro and disable its background helper in macOS System Settings → General → Login Items & Extensions. Do not remove Island Pro yet. Its existing daemon or process blocks this app from registering or enabling its own helper.
2. Put `Shut Your Lid.app` in `/Applications` and launch it.
3. Click its laptop icon and turn on the switch. macOS must approve the new helper separately. Use «Открыть настройки macOS» and approve the background item for Shut Your Lid (macOS may display the developer name Artem Kharitonov).
4. Return to the app and open its menu again. The app refreshes authorization after returning to it and on panel opening. Only helper confirmation displays on.
5. Keep the app running. Complete the physical lid test below before relying on it.

No old permission, TCC entry, state file or XPC identity is reused. Island Pro's source and installed app remain unchanged. Removing its closed-lid feature is a separate step after hardware acceptance.

## Protections

- Own signed SMAppService daemon: `com.artemkharitonov.shutyourlid.power`.
- Own app: `com.artemkharitonov.shutyourlid`.
- Own executable: `LidPowerHelper`; both directions require the expected code signing identifier and Developer ID team `8XZ7Z4UR6C`.
- Root-owned private persistence: `/Library/Application Support/ShutYourLid/com.artemkharitonov.shutyourlid.lid-mode.json`.
- Writes previous sleep state before changing `pmset disablesleep`; restores on disable, disconnect, lease expiry, guard or daemon restart.
- Default four-hour limit, 10% battery floor, serious/critical thermal stop, 30-second app heartbeat and 90-second lease; daemon checks every ten seconds.
- Refuses to start if sleep is already disabled by another tool. Refuses the known Island Pro stable/beta daemons and running Island Pro process. Rechecks conflict during operation. This is a conservative migration gate, not a universal lock against arbitrary tools changing pmset after enable.
- At 10% battery or below, normal sleep is restored and the Mac is asked to sleep even with its lid open. The ten-second guard interval bounds normal detection latency. Known AC power does not trigger the low-battery stop. Unknown source or missing/invalid battery charge blocks enable and stops a running mode.
- Continuous monotonic time, including system sleep, drives duration and heartbeat deadlines; changing the wall clock cannot extend them. Calendar dates are used only for display and crash records.
- A failed restoration preserves the recovery file, reports an error and retries on the daemon timer. A corrupt file blocks enable instead of guessing a previous state.

This uses a privileged system setting, not caffeinate. The physical lid behavior has not been verified on this Mac, and no claim is made for all Mac models. Avoid putting an operating laptop in a bag.

## Build and verify

```sh
swift test
./Scripts/build-app.sh /private/tmp/shut-your-lid-artifact
python3 Scripts/verify-app.py '/private/tmp/shut-your-lid-artifact/Shut Your Lid.app'
```

The build script signs with the owner's installed Developer ID certificate. Private signing keys remain in the build machine’s Keychain and are not packaged. The runtime application and daemon contain no Keychain-reading, document-reading, analytics or network client code. Each installation operates on its own Mac with its own local state. Signing identifies the publisher but grants no access to the publisher’s computer or Keychain. It does not install signing credentials, register the daemon, change power settings or request permissions. Build in a local temporary folder to avoid File Provider metadata interfering with signing. The release script remaps source paths, removes debug symbol references before signing, and rejects personal paths or secret patterns in artifacts. Run `python3 Scripts/privacy-gate.py --history --app /path/to/app` before publication. These static checks complement code review; they are not a proof against every possible vulnerability. Icon source is the native drawing script `Scripts/make-icon.swift`.

## Physical acceptance

After disabling the old mode, approving the new app, and seeing its switch on:

```sh
python3 Scripts/lid-check.py record --out /private/tmp/shut-your-lid-check.jsonl
```

Wait ten seconds, note the time, close the lid for at least two minutes, open it and wait ten seconds. Stop the recorder with Ctrl-C. Then inspect:

```sh
python3 Scripts/lid-check.py inspect --out /private/tmp/shut-your-lid-check.jsonl
```

The recorder checks the migration gate, running new app/helper and the real flag before recording. Each sample executes background work and writes a wall-clock timestamp; inspect reports gaps over ten seconds. A clean gap report alone is not proof that the lid was closed: the owner must record actual close/open times and confirm the interval was covered. Repeat on battery and with the intended external display/power setup. Then switch off and confirm `pmset -g` no longer reports `SleepDisabled 1`. Quit and repeat app disconnect/recovery tests if desired. Do not disable an unrelated tool's power flag.

## Provenance

Only the lid controller/protocol/model, helper, compact menu and related tests were extracted from the owner's Island Pro project at commit `2d03a54` (`audit/beta2-fixes`, build 40032). No Island Pro updater, cloud integrations, profile or broader app source was copied. Historical test results are not evidence of hardware acceptance for this app.
