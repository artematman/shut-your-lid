# Security

Shut Your Lid is a local macOS utility with a privileged power helper. It has no runtime network client or Keychain-reading code. It is not sandboxed and cannot promise absolute security.

## Release policy

Do not publish a stable binary until the exact packaged artifact passes signature, privacy, launch-constraint and notarization checks, and the helper is tested on a separate test Mac or VM. Validate denied XPC clients, handled termination, recovery, battery/thermal guards and real lid closure. Automated tests use simulated power settings and cannot establish hardware acceptance.

## Reporting

Do not post keys, personal data or exploit details in a public issue. Use the repository’s private vulnerability reporting when enabled. Until that channel is enabled, withhold sensitive reports; no private reporting address is configured here.

## Signing

Only the public code signature and certificate travel with the app. The signer’s private key and notarization credentials stay on the build machine. A recipient never needs the publisher’s credentials. The app and helper validate fixed identities rather than accepting arbitrary callers.
