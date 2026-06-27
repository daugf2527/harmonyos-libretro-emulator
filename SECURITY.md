# Security Policy

## Supported Scope

This repository is actively maintained around the `new_arch` HarmonyOS frontend path.

Security-sensitive areas include:

- NAPI boundary code under `entry/src/main/cpp/app/napi/`
- Native rendering and buffer access
- File import / sandbox path handling
- Dynamic core loading

## Reporting a Vulnerability

Please do not open a public issue for suspected security problems.

Report with:

- affected file or area
- reproduction steps
- impact summary
- logs or screenshots if safe to share

Current private contact path:

- See [SUPPORT.md](SUPPORT.md) and replace the placeholder release contact with the project owner contact before public release.

## What Counts as High Risk Here

- Path traversal or unsafe file access
- Loading untrusted native core binaries from writable locations without validation
- Native buffer misuse
- Cross-thread unsafe NAPI usage
- Secret or signing material leakage

## Response Expectations

- Triage first, patch second.
- Fix the root cause, not only the symptom.
- Add or update a guard script when the issue can regress silently.
