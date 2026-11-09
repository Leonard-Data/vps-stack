# Manual install — step by step

Follow this when you want to understand or repair the host, or when a module in
`install.sh` fails and you need to do its work by hand. Every step is the exact
command the matching module runs; the module numbers line up.

Each step says what it installs, **why it is in that position**, and how to
verify it before moving on. Do not skip a verification: a later module assumes
the earlier one's end state.

**Order matters in three places, and only three:**
- Tailscale (10) before dsh (70) — dsh binds the tailnet IP and Ovis publishes
  itself with `tailscale serve`.
- Docker (20) before apps (80), and **Traefik before every other app** — Traefik
  owns `:80`/`:443` and the ACME challenge.
- 9router (80) before you can actually use dsh or OpenViking extraction — both
  call it, and its API key only exists after its first boot.

Everything else is independent and can be done in any order.

---

## 0. Prerequisites

A fresh Ubuntu 24.04 host, root over SSH, and a DNS A record for
`*.<your-domain>` pointing at it (Traefik needs it for certificates).

```bash
ssh root@<host>
apt-get update && apt-get install -y git
git clone https://github.com/Leonard-Data/vps-stack /opt/vps-stack
cd /opt/vps-stack
cp .env.example .env
$EDITOR .env          # fill everything in — see docs/DOTENV.md
node scripts/render-env.mjs check
```

`.env` is the only file you ever edit by hand. Every app's env file, `ov.conf`
and the dsh profile patch are rendered from it.

---

## 1. Base packages (module `00-base`)

**Why first:** `build-essential` is needed by native builds inside the dsh
plugin install, `jq`/`sqlite3` by the agents' own scripts, `tmux` by firstmate's
backend, and `gh` by the agents' release workflows.

```bash
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y build-essential ca-certificates curl wget git gnupg jq \
  unzip sqlite3 tmux screen byobu htop net-tools vim nano python3 \
  software-properties-common

# GitHub CLI, from its own apt repo
mkdir -p -m 755 /etc/apt/keyrings
wget -nv -O /etc/apt/keyrings/githubcli-archive-keyring.gpg https://cli.github.com/packages/githubcli-archive-keyring.gpg
chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list
apt-get update && apt-get install -y gh

git config --global user.name "<you>"
git config --global user.email "<you@example.com>"
git config --global init.defaultBranch main
```

**Verify:** `gh --version` and `jq --version` both answer.

---

## 2. Tailscale (module `10-tailscale`)

**Why here:** it is the *only* network path to the Web UIs. dsh binds to the
tailnet IP, and the Ovis installer publishes the UI with `tailscale serve` when
it finds Tailscale running — install it later and Ovis is reachable only on
loopback.

```bash
curl -fsSL https://tailscale.com/install.sh | sh
systemctl enable --now tailscaled
tailscale up --authkey "$TS_AUTHKEY" --hostname srv2119237 --ssh
tailscale ip -4
```

**Verify:** `tailscale status` lists this node as the current machine, and the
IPv4 it prints matches `DSH_BIND_IP` in `.env`. If it does not, put the real one
in `.env` now — module 70 writes it into the systemd unit.

---

## 3. Docker (module `20-docker`)

**Why here:** every composed application needs it, and nothing before this does.

```bash
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \$(. /etc/os-release && echo \$UBUNTU_CODENAME) stable" > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
```

**Verify:** `docker compose version` answers (the *plugin*, not the old
`docker-compose` binary — the compose files here use plugin syntax).

---

## 4. Node runtimes and uv (module `30-node`)

**Why two Node installs:** `/opt/node22` is the system Node that global CLIs are
installed into; dsh ships and pins its **own** Node under
`/root/.local/share/pi-node`. Keeping them separate is deliberate — upgrading one
must not break the other.

```bash
# system node
cd /tmp
curl -fsSL -o node.tar.xz https://nodejs.org/dist/v22.21.1/node-v22.21.1-linux-x64.tar.xz
tar -xf node.tar.xz
rm -rf /opt/node22 && mv node-v22.21.1-linux-x64 /opt/node22
ln -sf /opt/node22/bin/node /usr/local/bin/node
ln -sf /opt/node22/bin/npm  /usr/local/bin/npm
ln -sf /opt/node22/bin/npx  /usr/local/bin/npx
echo 'export PATH="/opt/node22/bin:$PATH"' >> /root/.bashrc

# global CLIs the agents call by name
npm install -g tasks-axi gh-axi quota-axi chrome-devtools-axi
for b in tasks-axi gh-axi quota-axi chrome-devtools-axi; do ln -sf /opt/node22/bin/$b /usr/local/bin/; done

# uv — runs the Hindsight daemon via uvx; installed system-wide because the
# unprivileged hindsight user needs it too
curl -fsSL https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh
```

**Verify:** `node -v` → `v22.21.1`, `uv --version` answers.

---

## 5. Pi agent (module `40-pi`)

**Why before firstmate:** firstmate's bootstrap installs hooks *into* pi and
reports it as MISSING otherwise.

```bash
curl -fsSL https://pi.dev/install.sh | sh
echo 'export PATH="/root/.pi/agent/bin:$PATH"' >> /root/.bashrc
export PATH="/root/.pi/agent/bin:$PATH"
pi --version
```

Then **sign in once, interactively** — this cannot be scripted:

```bash
pi            # follow the login prompt
```

**Verify:** `/root/.pi/agent/auth.json` exists. Credentials are never in this
repo.

---

## 6. herdr + Ovis (module `50-herdr-ovis`)

**Why one step:** Ovis is a *herdr plugin*, and its installer pulls herdr and Bun
when they are missing. Installing herdr separately first is allowed but
pointless.

```bash
curl -fsSL https://ovis.sh/install.sh | sh
ln -sf /root/.local/bin/herdr /usr/local/bin/herdr
```

What that installer does, in order: installs herdr (into `~/.local/bin`) and Bun
(into `~/.bun`) if absent; registers Ovis as the `devswha.ovis` herdr plugin so
it starts with herdr and self-updates; and, finding Tailscale up, serves the UI
to the tailnet and prints a QR code for a phone.

**Verify:**

```bash
herdr --version
herdr plugin list --json | grep -o devswha.ovis
ls /root/.config/ovis            # config dir exists
```

---

## 7. firstmate (module `60-firstmate`)

**Why after pi:** see step 5. It is a git checkout of shell tooling, not a
package.

```bash
git clone https://github.com/kunchenguid/firstmate /root/firstmate
cd /root/firstmate
mkdir -p config && echo tmux > config/backend      # terminals run through tmux here
bash bin/fm-bootstrap.sh
```

`fm-bootstrap.sh` is a *detector*: silence means everything it needs is present.
Any line starting `MISSING:`, `OUTDATED:` or `NEEDS_GH_AUTH` tells you exactly
what to install or authenticate — do that, then run it again.

**Verify:** `bash bin/fm-bootstrap.sh` prints nothing.

---

## 8. DeepSeek Harness (module `70-dsh`)

The biggest step. Four parts: pinned Node, the CLI, the profile, the service.

### 8a. The runtime dsh pins

```bash
mkdir -p /root/.local/share/pi-node && cd /root/.local/share/pi-node
curl -fsSL -o node.tar.xz https://nodejs.org/dist/v24.22.2/node-v24.22.2-linux-x64.tar.xz
tar -xf node.tar.xz && rm node.tar.xz
ln -sfn /root/.local/share/pi-node/node-v24.22.2-linux-x64 /root/.local/share/pi-node/current
export PATH="/root/.local/share/pi-node/current/bin:$PATH"
corepack enable                 # provides the pnpm dsh installs plugins with
```

The `current` symlink is the point: the systemd unit's `PATH` points at it, so a
runtime upgrade is a re-point and a restart.

### 8b. The CLI

```bash
npm install -g @deepseek-ai/dsh@0.2.2-rc.1
dsh --version
```

### 8c. The `web` profile

The profile is **declarative**: `package.json` names the plugins and the bundle
load order, `cordis.patch.yml` configures them. Both are tracked in this repo,
which is why a rebuilt host gets *this* harness and not a default one.

```bash
export DSH_HOME=/root/.dsh
mkdir -p /root/.dsh/profiles/web
cp /opt/vps-stack/profiles/web/package.json /root/.dsh/profiles/web/package.json
node /opt/vps-stack/scripts/render-env.mjs dsh-patch > /root/.dsh/profiles/web/cordis.patch.yml

# four plugins are linked by path, so their checkouts must exist first
STACK_ROOT=/opt/vps-stack /opt/vps-stack/scripts/clone-local-plugins.sh

cd /root/.dsh/profiles/web
dsh plugin --profile web install        # pnpm; several minutes
```

**Verify:** `ls /root/.dsh/profiles/web/node_modules` lists the plugin packages,
and no `link:` dependency is unresolved.

### 8d. The service

```bash
cat > /etc/systemd/system/dsh.service <<'UNIT'
[Unit]
Description=DeepSeek Harness web UI (dsh)
After=network-online.target tailscaled.service
Wants=network-online.target

[Service]
Environment=PATH=/root/.local/share/pi-node/current/bin:/usr/local/bin:/usr/bin:/bin
Environment=DSH_HOME=/root/.dsh
WorkingDirectory=/root
ExecStart=/root/.local/share/pi-node/current/bin/dsh web --no-open \
  --host 100.96.88.73 --port 3080 \
  --trusted-host srv2119237.taile20a22.ts.net \
  --trusted-host srv2119237 \
  --trusted-host localhost
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now dsh
```

Replace `--host` with *your* tailnet IP and the `--trusted-host` values with your
tailnet names. dsh rejects a request whose `Host` header it does not trust, so a
wrong value here shows up as a blank page, not an error.

**Verify:** `systemctl is-active dsh` → `active`, and
`curl -sI http://<tailnet-ip>:3080/` returns a 200.

---

## 9. Hindsight memory daemon (module `75-hindsight`)

**Why an unprivileged user:** it indexes repositories and calls an LLM. It gets
its own account and no more.

```bash
useradd --create-home --shell /usr/sbin/nologin hindsight

mkdir -p /root/.hindsight
cat > /root/.hindsight/coding-agent.json <<'JSON'
{ "serverMode": "daemon", "apiPort": 9077, "daemonProfile": "coding-agent" }
JSON

install -m 0755 /opt/vps-stack/scripts/hindsight-healthcheck.sh /usr/local/bin/

cat > /etc/systemd/system/hindsight-daemon.service <<'UNIT'
[Unit]
Description=Hindsight local memory daemon (embedded, unprivileged user)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
User=hindsight
Group=hindsight
Environment=HOME=/home/hindsight
Environment=PATH=/usr/local/bin:/usr/bin:/bin
WorkingDirectory=/home/hindsight
ExecStart=/usr/local/bin/uvx hindsight-embed@latest -p coding-agent daemon start
ExecStop=/usr/local/bin/uvx hindsight-embed@latest -p coding-agent daemon stop
TimeoutStartSec=900

[Install]
WantedBy=multi-user.target
UNIT
```

`TimeoutStartSec=900` is not padding: the first start resolves and builds a
Python environment through `uvx`.

The timer exists because the daemon can wedge without exiting. It requires **two
consecutive** failures (~4 minutes) before restarting, so a slow cold start does
not bounce it:

```bash
cat > /etc/systemd/system/hindsight-healthcheck.service <<'UNIT'
[Unit]
Description=Hindsight daemon health check and auto-restart
After=hindsight-daemon.service
[Service]
Type=oneshot
ExecStart=/usr/local/bin/hindsight-healthcheck.sh
UNIT

cat > /etc/systemd/system/hindsight-healthcheck.timer <<'UNIT'
[Unit]
Description=Run the Hindsight daemon health check every 2 minutes
[Timer]
OnBootSec=2min
OnUnitActiveSec=2min
AccuracySec=15s
[Install]
WantedBy=timers.target
UNIT

systemctl daemon-reload
systemctl enable --now hindsight-daemon.service hindsight-healthcheck.timer
```

**Verify:** `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:9077/health`
→ `200` (allow a minute or two on the very first start).

---

## 10. Composed applications (module `80-apps`)

**Traefik must be first.** It is the only process bound to `:80`/`:443` and it
answers the ACME challenge; bring an app up before it and that app has nowhere
to register.

```bash
cd /opt/vps-stack
node scripts/render-env.mjs apps        # writes every app's .env + ov.conf

# Traefik — TLS edge
mkdir -p /docker/traefik-twp8
cp apps/traefik/docker-compose.yml /docker/traefik-twp8/
cd /docker/traefik-twp8 && docker compose up -d

# 9router — LLM proxy everything else calls
mkdir -p /docker/9router-nxkt
cp /opt/vps-stack/apps/9router/docker-compose.yml /docker/9router-nxkt/
cd /docker/9router-nxkt && docker compose up -d

# hermes — the VPS provider's agent
mkdir -p /docker/hermes-agent-qila
cp /opt/vps-stack/apps/hermes/docker-compose.yml /docker/hermes-agent-qila/
cd /docker/hermes-agent-qila && docker compose up -d

# OpenViking — memory server + local embedding model
cd /root/plugins/openviking-server && docker compose up -d
docker exec openviking-ollama ollama pull nomic-embed-text
```

The compose **project name is the Traefik subdomain** (`9router-nxkt` answers on
`9router-nxkt.<your-domain>`), which is why the directory names are not
arbitrary.

**Verify:**

```bash
docker compose ls                  # four projects, all running
curl -sI https://9router-nxkt.<your-domain>     # 200 and a real certificate
curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:1933/   # OpenViking
```

---

## 11. The interactive steps nothing can script

These need a human and a browser, in this order:

1. **9router API key.** Open `https://9router-nxkt.<your-domain>`, sign in with
   `INITIAL_PASSWORD`, mint an API key. Put it in `.env` as
   `NINEROUTER_API_KEY`, then re-render and restart what consumes it:
   ```bash
   cd /opt/vps-stack && ./install.sh --only apps --force
   ```
   Until this is done, dsh's `9router` provider and OpenViking's memory
   extraction both fail at the first call — the containers are up, the key is
   simply not minted yet.
2. **pi sign-in** — `pi`, step 5.
3. **gh sign-in** — `gh auth login -s project,workflow` (the `project` scope is
   needed for Projects v2 boards; without it `gh project list` fails with
   *missing required scopes*).
4. **OpenViking user key.** The dsh memory plugin authenticates with a *user*
   key, not the root key. Mint one against the running server with the root key
   from `.env`, then save it to `/root/.openviking/ovcli.conf`:
   ```json
   { "url": "http://127.0.0.1:1933", "api_key": "<user key>" }
   ```
5. **Tailscale operator** (optional, for a non-root user):
   `tailscale set --operator=$USER`.

---

## 12. Final verification

```bash
/opt/vps-stack/scripts/doctor.sh
```

It checks every module's observable end state — runtimes, agents, services,
endpoints, containers — and exits non-zero with the count of failures. This is
the same check `install.sh` runs at the end.
