# Module reference

Ten ordered, idempotent modules. Each records `/var/lib/vps-stack/<name>.done`
and skips itself on a re-run unless `--force`. A failure stops the run so
`--from <module>` can resume it.

| # | Module | Installs | Hard dependency | End state to verify |
|---|---|---|---|---|
| 00 | `base` | apt packages, `gh`, git identity | — | `gh --version` |
| 10 | `tailscale` | `tailscaled`, tailnet join | — | `tailscale status` shows this node |
| 20 | `docker` | docker-ce + compose plugin | — | `docker compose version` |
| 30 | `node` | `/opt/node22`, `*-axi` CLIs, `uv` | base | `node -v`, `uv --version` |
| 40 | `pi` | Pi agent under `~/.pi/agent` | — | `pi --version` |
| 50 | `herdr-ovis` | herdr, Bun, Ovis herdr plugin | tailscale *(for tailnet serve)* | `herdr plugin list` shows `devswha.ovis` |
| 60 | `firstmate` | `/root/firstmate` checkout + hooks | pi, node | `fm-bootstrap.sh` silent |
| 70 | `dsh` | pinned Node, dsh CLI, web profile, `dsh.service` | node, tailscale | `systemctl is-active dsh` |
| 75 | `hindsight` | unprivileged user, daemon unit, health timer | node *(uv)* | `:9077/health` → 200 |
| 80 | `apps` | traefik → 9router → hermes → openviking | docker | `docker compose ls`: 4 running |

## The four real dependencies

Everything else is independent; these are the orderings that actually matter.

1. **tailscale → dsh.** dsh binds the tailnet IP and trusts tailnet hostnames in
   the `Host` header. Install it later and the unit binds an address that does
   not exist yet.
2. **tailscale → ovis.** The Ovis installer runs `tailscale serve` when it finds
   Tailscale up. Out of order, Ovis is loopback-only.
3. **docker → traefik → every other app.** Traefik owns `:80`/`:443` and the
   ACME challenge.
4. **node (uv) → hindsight.** The daemon unit's `ExecStart` is `uvx`.

## Within-module ordering worth knowing

- **70-dsh** installs the runtime *before* the CLI (npm must run under the
  pinned Node), the profile manifest before `dsh plugin install`, and the local
  plugin checkouts before that, because four dependencies are `link:` paths.
- **80-apps** renders env files before any `compose up`, and pulls
  `nomic-embed-text` after OpenViking is up — the first embedding request would
  otherwise time out while the model downloads.

## Selective runs

```bash
./install.sh --list                   # the module graph
./install.sh --dry-run                # what would run
./install.sh --only dsh,apps          # just those two
./install.sh --from 70-dsh            # resume after a failure
./install.sh --only apps --force      # re-render env + recreate containers
APPS_ONLY=openviking ./install.sh --only apps --force   # one app
```
