# Contributing

## Before You Start

- Read [README.md](README.md) for project scope and current release boundary.
- Read [AGENTS.md](AGENTS.md) for repository-specific engineering constraints.
- Prefer changes in the active `new_arch` path. Do not extend `deprecated/legacy/` unless the task explicitly requires it.

## Development Environment

- Primary environment: Windows + DevEco Studio + HarmonyOS SDK.
- Main module: `entry`.
- Default target device type: `phone`.

## Recommended Workflow

1. Create a focused branch for one topic.
2. Keep changes small and reviewable.
3. Run the local guards before opening a PR.
4. Update docs when behavior, release boundary, or contributor workflow changes.

## Local Checks

Run these before submitting:

```bash
bash scripts/ci/check_repo_hygiene.sh
bash scripts/ci/check_regression_guards.sh
bash scripts/check/quick_signals.sh
```

If you changed release-facing assets or metadata, also run:

```bash
bash scripts/ci/check_release_readiness.sh
```

## Code and Review Expectations

- Prefer boring, minimal fixes over wide refactors.
- Match existing patterns in ArkTS, NAPI, and engine code.
- Do not commit generated build output, local SDK state, or secrets.
- Do not add bundled ROM content, BIOS payloads, or unreviewed cover-art assets to release-bound resources.

## Pull Requests

- Explain what changed and why.
- List the checks you ran locally.
- Call out anything not verified on device.
- Include screenshots for UI changes when relevant.

## Documentation

- Put stable contributor and product docs under `docs/`.
- Put release-facing material under `docs/release/`.
- Move obsolete audit material to `docs/archive/` instead of leaving it at the root.
