# Dotenv management

## One file, rendered outward

```
.env  (git-ignored, mode 600, the only file you edit)
  │
  └─ scripts/render-env.mjs
       ├─ /docker/<9router>/.env        COMPOSE_PROJECT_NAME, TRAEFIK_HOST, 4 secrets
       ├─ /docker/<traefik>/.env        COMPOSE_PROJECT_NAME, ACME_EMAIL
       ├─ /docker/<hermes>/.env         COMPOSE_PROJECT_NAME, TRAEFIK_HOST
       ├─ <openviking-server>/ov.conf   root key, embedding, extraction endpoint
       └─ ~/.dsh/profiles/web/cordis.patch.yml   the 9router provider baseURL
```

Everything below `.env` is a **rendered artifact**: overwritten on every run,
git-ignored, and never edited in place. A secret therefore exists in exactly one
place, and a rebuilt host cannot drift from the file that describes it.

Why a renderer rather than `env_file:` everywhere: `ov.conf` is JSON, the dsh
patch is YAML, and Compose only interpolates its own file. One renderer covers
all three formats and fails loudly on a missing key.

## Commands

| Command | Does |
|---|---|
| `node scripts/render-env.mjs check` | Validates `.env`: required keys present, no leftover placeholders. |
| `node scripts/render-env.mjs apps` | Renders every app env file and `ov.conf` (mode `600`). |
| `node scripts/render-env.mjs dsh-patch` | Prints the rendered `cordis.patch.yml` to stdout. |
| `node scripts/self-check.mjs` | The repo's own test: substitution, failure modes, and that every `\${KEY}` in every template has a source. |

`install.sh` runs `check` before the first module, so an incomplete `.env` fails
in two seconds instead of halfway through a plugin install.

## An empty value is an error, not a blank

`render()` throws on a key that is missing **or empty**. A blank substitution
would write `api_key: ""` into `ov.conf` and the stack would fail much later,
somewhere unrelated. `scripts/self-check.mjs` asserts this directly.

## Rotating a secret

```bash
$EDITOR /opt/vps-stack/.env          # change the value
cd /opt/vps-stack
./install.sh --only apps --force     # re-render + recreate the containers
```

For a key the harness itself consumes (`NINEROUTER_API_KEY` in the dsh provider
config), also re-render the profile patch and restart:

```bash
node scripts/render-env.mjs dsh-patch > /root/.dsh/profiles/web/cordis.patch.yml
systemctl restart dsh
```

## Which keys are actually secret

| Key | Where it ends up | Rotate by |
|---|---|---|
| `TS_AUTHKEY` | used once by `tailscale up`, never stored | mint a new key; existing node stays joined |
| `JWT_SECRET`, `API_KEY_SECRET`, `MACHINE_ID_SALT` | 9router env | rotating invalidates issued 9router keys |
| `INITIAL_PASSWORD` | 9router env | only used before the first UI sign-in |
| `OPENVIKING_ROOT_API_KEY` | `ov.conf` | re-render, restart the `openviking` container |
| `NINEROUTER_API_KEY` | `ov.conf` + the dsh provider | re-render both, restart `openviking` and `dsh` |

Non-secret but host-specific: `TRAEFIK_HOST`, `ACME_EMAIL`, `DSH_BIND_IP`,
`TS_FQDN`, and the three `*_PROJECT` names — the compose project name *is* the
Traefik subdomain, so changing one moves a URL.

## Backing it up

`.env` is the one file worth backing up: with it plus this repo, the host is
reproducible. Without it, every credential must be re-minted.

```bash
install -m 600 /opt/vps-stack/.env /root/backups/vps-stack.env.$(date +%F)
```
