# Docs Index

This directory contains the project's long-lived documentation.

## Start Here

- Project overview: [../README.md](../README.md)
- Contributor workflow: [../CONTRIBUTING.md](../CONTRIBUTING.md)
- Repository constraints: [../AGENTS.md](../AGENTS.md)
- Release boundary: [release/appgallery-readiness-checklist.md](release/appgallery-readiness-checklist.md)

## Main Sections

- `architecture/`
  - Stable architecture and subsystem references
- `reference/`
  - Long-lived implementation references, API notes, and support material
- `design/`
  - UI, feature, and implementation design docs
- `plans/`
  - Execution plans and implementation roadmaps
- `release/`
  - AppGallery/store-release material and policy docs
- `verification/`
  - Verification checklists and validation references
- `audit/`
  - Active audit and investigation material still worth referencing
- `archive/`
  - Historical or superseded material kept for traceability

## Reading Order for New Contributors

1. [../README.md](../README.md)
2. [architecture/](architecture/)
3. [reference/](reference/)
4. [design/](design/)
5. [release/](release/)

## Doc Hygiene Rules

- Keep stable docs near the top-level section folders above.
- Keep only a small set of high-signal entry documents at `docs/` root.
- Put generated drift reports under `archive/gc/` instead of the root.
- Move obsolete or one-off investigation output to `archive/`.
- Avoid leaving important contributor guidance only inside session-specific plans or audits.
