# vps-stack

[![CI](https://github.com/Leonard-Data/vps-stack/actions/workflows/ci.yml/badge.svg)](https://github.com/Leonard-Data/vps-stack/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/Leonard-Data/vps-stack?sort=semver)](https://github.com/Leonard-Data/vps-stack/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Reproduce one agent VPS exactly — the [DeepSeek Harness](https://github.com/Leonard-Data/deepseek-harness)
(`dsh`), the [Pi](https://pi.dev) agent, [firstmate](https://github.com/kunchenguid/firstmate),
[Ovis](https://ovis.sh) + herdr, Tailscale, and the composed applications
(Traefik, 9router, Hermes, [OpenViking](https://github.com/Leonard-Data/openviking-server))
— from one SSH connection.

Three ways in, same end state:

- **One command.** `./install.sh` runs ten ordered, idempotent modules.
- **By hand.** [docs/MANUAL.md](docs/MANUAL.md) is every command with the reason
  it sits where it does, and what to verify before moving on.
- **One module.** `./install.sh --only dsh` to rebuild just the harness.

```
┌─ tailnet ───────────────────────────────────────────────────────────────┐
│  dsh web :3080        Ovis (herdr plugin, tailscale serve)              │
└─────────┬───────────────────────────────┬───────────────────────────────┘
          │                               │
   dsh web profile                  herdr session server ── pi ── firstmate
   18 bundles, 4 local plugins
          │
          ├── hindsight :9077  (systemd, unprivileged user, 2-min health timer)
          └── openviking :1933 (loopback only) ──┬── ollama  nomic-embed-text
                                                 └── 9router :32768 extraction
┌─ docker ────────────────────────────────────────────────────────────────┐
│  traefik :80/:443 ─ TLS edge ─┬─ 9router  ─┬─ hermes-agent              │
│                               └─ openviking + ollama                   │
└─────────────────────────────────────────────────────────────────────────┘
```

## Quick start

```bash
ssh root@<host>
apt-get update && apt-get install -y git
git clone https://github.com/Leonard-Data/vps-stack /opt/vps-stack
cd /opt/vps-stack
cp .env.example .env && $EDITOR .env     # the only file you edit by hand
./install.sh
```

Or in one line, on a bare host:

```bash
curl -fsSL https://raw.githubusercontent.com/Leonard-Data/vps-stack/main/install.sh | bash
# clones to /opt/vps-stack and re-execs; stops until you fill in .env
```

`install.sh` refuses to start on an incomplete `.env`, so a missing secret fails
in two seconds rather than halfway through a plugin install.

## What gets installed

| Module | Component | Where it lands |
|---|---|---|
| `00-base` | apt packages, `gh`, git identity | system |
| `10-tailscale` | `tailscaled` + tailnet join | system |
| `20-docker` | docker-ce + compose plugin | system |
| `30-node` | Node 22, `*-axi` CLIs, `uv` | `/opt/node22`, `/usr/local/bin` |
| `40-pi` | Pi agent | `/root/.pi/agent` |
| `50-herdr-ovis` | herdr, Bun, Ovis plugin | `/root/.local/bin`, `/root/.config/ovis` |
| `60-firstmate` | firstmate checkout + hooks | `/root/firstmate` |
| `70-dsh` | pinned Node, dsh CLI, `web` profile, `dsh.service` | `/root/.dsh` |
| `75-hindsight` | memory daemon + health timer | `hindsight` user, systemd |
| `80-apps` | traefik → 9router → hermes → openviking | `/docker/*`, `/root/plugins/openviking-server` |

Full table with dependencies and verification: [docs/MODULES.md](docs/MODULES.md).

## Running it again

Modules are idempotent: each writes `/var/lib/vps-stack/<name>.done` and skips
itself unless `--force`. A failure stops the run so you can resume:

```bash
./install.sh --list              # the module graph
./install.sh --dry-run           # what would run
./install.sh --only dsh,apps     # a subset
./install.sh --from 70-dsh       # resume after a failure
./install.sh --only apps --force # re-render env files and recreate containers
```

## Configuration

`.env` is the single source of truth. Every app env file, `ov.conf`, and the dsh
profile patch are **rendered** from it by `scripts/render-env.mjs` and are
git-ignored — a secret lives in exactly one place.

```bash
node scripts/render-env.mjs check   # validate .env
node scripts/render-env.mjs apps    # re-render every artifact
node scripts/self-check.mjs         # this repo's own test
```

See [docs/DOTENV.md](docs/DOTENV.md) for the key-by-key table and rotation.

## Verifying

```bash
./scripts/doctor.sh
```

Checks every module's observable end state — runtimes, agents, services,
endpoints, containers — and exits with the number of failures. `install.sh` runs
it automatically at the end.

## Architecture diagram

[`docs/architecture.html`](docs/architecture.html) is a standalone, explorable
[Archify](https://github.com/tt-a1i/archify) diagram of the module graph: which
module installs what, the four orderings that actually matter, and the trust
boundaries (tailnet / loopback / Docker network / public TLS edge). Open the file
in a browser — no server needed.

## What this repo cannot do

Four steps need a human, and `install.sh` prints them at the end:

1. `pi` — interactive sign-in.
2. `gh auth login -s project,workflow` — device flow.
3. The **9router API key**, minted in its Web UI after first boot. Until then
   dsh's `9router` provider and OpenViking's memory extraction both fail at the
   first call.
4. The **OpenViking user key** for the dsh memory plugin
   (`/root/.openviking/ovcli.conf`).

Credentials are never committed; `.env` is git-ignored and every rendered
artifact is written `600`.

## Related repos

| Repo | What it is |
|---|---|
| [openviking-server](https://github.com/Leonard-Data/openviking-server) | The OpenViking compose stack (owns its own `docker-compose.yml`) |
| [openviking-viewer](https://github.com/Leonard-Data/openviking-viewer) | dsh Web UI panel for browsing memory |
| [hindsight-graph](https://github.com/Leonard-Data/hindsight-graph) | dsh Web UI panel: the Hindsight memory graph |
| [docker-compose-panel](https://github.com/Leonard-Data/docker-compose-panel) | dsh Web UI panel for the compose projects above |

## License

MIT — see [LICENSE](LICENSE).
