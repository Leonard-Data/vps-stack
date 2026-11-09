# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-11-09

First release: the surveyed VPS, reproducible from one SSH connection.

### Added

- `install.sh` — ten ordered, idempotent modules with `--only`, `--from`,
  `--force`, `--dry-run` and `--list`; resumable after a failure.
- Modules for apt base, Tailscale, Docker, the two Node runtimes + `uv`, the Pi
  agent, herdr + Ovis, firstmate, the DeepSeek Harness (pinned runtime, `web`
  profile and `dsh.service`), the Hindsight daemon with its health timer, and the
  four composed applications.
- Dotenv management: one git-ignored `.env` renders every app env file,
  `ov.conf`, and the dsh profile patch via `scripts/render-env.mjs`; an empty
  value is a hard error, never a blank substitution.
- `scripts/doctor.sh` — one check over every module's observable end state.
- `scripts/self-check.mjs` — the repo's own test for the renderer and the
  module/template consistency invariants.
- `docs/MANUAL.md` — step-by-step manual install, each step with its ordering
  rationale and verification.
- `docs/MODULES.md`, `docs/DOTENV.md` — module reference and dotenv management.
- `docs/architecture.html` — Archify diagram of the module graph and its trust
  boundaries.
