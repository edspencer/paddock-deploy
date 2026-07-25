# Docker recipe

Run Paddock with Docker Compose on a single VM or LXC container — the simplest
way to self-host. This is also the simplest Proxmox story: run Docker inside an
LXC and use this recipe unchanged.

It runs either official image:

- `ghcr.io/edspencer/paddock:latest` — **base** (app + `git` / `gh` / `claude`)
- `ghcr.io/edspencer/paddock:devbox` — base + `pm`, `ffmpeg`, a headless
  Playwright browser, and the Docker CLI

## What this recipe gives you

- A single `docker-compose.yml` with two profiles — **base** and **devbox** —
  so you pick your image with one flag.
- A persistent `paddock-data` volume mounted at `/data` (project store + Claude
  session transcripts, so restarts and resume keep working).
- A container healthcheck against `/api/health`.
- Loopback-only publishing (`127.0.0.1:4000`) — closed by default (see
  [Security](#security)).
- An optional docker-outside-of-docker socket mount for the devbox, so
  in-container `docker` builds/runs work.

## Quickstart

Prerequisites: Docker Engine + the Compose plugin on the host.

```sh
# 1. Grab the recipe
git clone https://github.com/edspencer/paddock-deploy
cd paddock-deploy/docker

# 2. Configure your token
cp .env.example .env
$EDITOR .env            # paste your CLAUDE_CODE_OAUTH_TOKEN

# 3a. Start the BASE image
docker compose --profile base up -d

# ...or 3b. start the DEVBOX image (coding-agent toolbox)
docker compose --profile devbox up -d

# 4. Check health
curl -fsS http://127.0.0.1:4000/api/health     # -> {"ok":true}
```

Then open <http://127.0.0.1:4000> on the host (or tunnel to it — see
[Security](#security)).

Get a Claude Max/Pro token by running `claude setup-token` on a machine where
you're logged in, and paste it into `.env`. To use the API instead, set
`ANTHROPIC_API_KEY` and leave the OAuth token empty.

> **Pick one profile at a time.** Both services publish the same host port, so
> `--profile base` and `--profile devbox` are mutually exclusive. They share the
> same `paddock-data` volume, so you can stop one and start the other without
> losing data.

Common operations:

```sh
docker compose --profile devbox logs -f     # tail logs
docker compose --profile devbox ps          # status + health
docker compose --profile devbox down        # stop (keeps the data volume)
docker compose --profile devbox down -v     # stop AND delete the data volume
```

## Base vs. devbox

The **base** image is all a stock Paddock instance needs: the app plus `git`,
`gh`, and the `claude` CLI. Use it when your agents mostly read, write, and
reason over text and code.

The **devbox** image adds the software-engineering toolbox — `pm` (a PM2-based
wrapper that runs preview servers on stable ports), `ffmpeg`, the Playwright MCP
browser (headless Chromium), and the Docker CLI. Use it when your agents build
and run apps.

The devbox only adds *tools*. The conventions for how agents use them (for
example "run preview servers under `pm`") live in an instance-wide `CLAUDE.md`
you mount into the data volume — never baked into an image. Copy
[`../CLAUDE.md.example`](../CLAUDE.md.example) to `docker/CLAUDE.md`, adapt it,
and uncomment the `./CLAUDE.md:/data/CLAUDE.md:ro` line in `docker-compose.yml`.

## Docker in the devbox

The devbox ships the Docker **CLI** only — no daemon, no privilege baked in. The
recipe wires **docker-outside-of-docker** by default: it bind-mounts the host's
`/var/run/docker.sock`, so an in-container `docker build`/`docker run` executes
on the **host** daemon.

This is cheap and needs no nested privilege, but it is a real trust decision:
anything in the container can drive the host daemon, which is effectively
root-level access to the host. Only mount the socket for keepers you trust, and
comment the line out if you don't need in-container Docker.

If you need an **isolated** daemon instead (nothing touching the host's), the
alternative is privileged Docker-in-Docker: run a `:dind` daemon as a sidecar
and point `DOCKER_HOST` at it. That keeps the host daemon untouched but requires
`privileged: true` (broad host capabilities — a weaker container boundary) plus
running and maintaining a second daemon and its storage. Prefer the socket mount
unless you specifically need daemon isolation. See the commented block in
`docker-compose.yml`.

## Security

Paddock has **no built-in password auth**. This recipe publishes to **loopback
only** (`127.0.0.1:4000`), and `PADDOCK_AUTH_MODE` defaults to `none`, so out of
the box the instance is reachable only from the host itself.

To reach it from another machine, keep the loopback publish and put a reverse
proxy / auth sidecar (nginx, oauth2-proxy, Authelia, Cloudflare Access, …) in
front, then set a matching auth mode (`PADDOCK_AUTH_MODE=trusted-header` or
`jwt`). Don't change the publish to a routable address (e.g. `0.0.0.0:4000:4000`)
without a real auth mode in front of it.

### Why `PADDOCK_DANGEROUSLY_ALLOW_OPEN=1` is set in the compose

Paddock **fails closed**: its app-layer guard
([paddock#435](https://github.com/edspencer/paddock/issues/435)) refuses to start
if it's bound to a non-loopback address with auth disabled. Inside a container
the app *always* binds `0.0.0.0` — Docker's port publishing can't route to an
in-container `127.0.0.1`, so the image binds all interfaces on purpose. That
tripping the guard is expected, so this recipe sets
`PADDOCK_DANGEROUSLY_ALLOW_OPEN=1` to let the app boot.

This does **not** expose your instance. For a container the real boundary is the
**network namespace plus the loopback host-publish** (`127.0.0.1:4000`), not the
in-container bind — the app is still reachable only from the host. (paddock's
`bind-safety.ts` explicitly hands this "safe publish posture" to the deploy
recipe.) If you ever publish on a routable address, unset this and put a real
auth mode in front instead.

Read the **Securing Paddock** guide at <https://paddock.edspencer.net> before
exposing an instance to any network.

## Remote MCP (the Management API)

Paddock **v0.46.0+** serves a remote MCP endpoint at **`/mcp`**, so a Claude Code
session on another machine — or a peer Paddock — can list projects, read chats,
and (if you let it) start turns on this instance.

This recipe is the **reference configuration** for it, because it has no proxy
at all: **Paddock authenticates `/mcp` itself**, with a per-client bearer token,
independently of `PADDOCK_AUTH_MODE` and of any reverse proxy. A proxy is an
operator's choice, never a prerequisite. The recipes under
[`../auth-basic/`](../auth-basic/) have to *exempt* `/mcp` from their edge gate
precisely because the edge was never what protected it.

It is **off until you turn it on**, and it fails closed:

| Request to `/mcp` | Result |
| --- | --- |
| No management clients configured | **404** — the endpoint does not exist |
| No credential | **401** + `WWW-Authenticate: Bearer realm="paddock"` |
| Wrong bearer token | **401** |
| Valid bearer token | **200**, MCP session |
| Plaintext from a non-loopback client | **403** `insecure_transport` |

### Turning it on

**1. Mint a token, one per client.** The `pdk_<instanceId>_` prefix binds it to
this instance, so a copy is useless at any other Paddock. Minimum 24 characters.

```sh
printf 'pdk_%s_%s\n' myinstance "$(openssl rand -hex 24)"
```

**2. Put it in `.env`** (gitignored) as `PADDOCK_MCP_TOKEN_LAPTOP=…`. The compose
file already passes that variable through to the container.

**3. Declare the client** in `paddock.config.yaml`. The credential is a
**reference**, never a literal — an inline `token:` is a hard config error,
because `paddock.config.yaml` is git-tracked and editable from the Settings
screen, so a secret written there would leak the moment it was committed.

```yaml
managementApi:
  instanceId: myinstance
  # The canonical public origin clients reach this instance at, no trailing
  # slash. Required. It must be what clients actually type — discovery compares
  # it byte-for-byte, and it can't be derived from the Host header.
  publicUrl: https://paddock.example.com
  clients:
    laptop:
      auth:
        type: token
        ref: env:PADDOCK_MCP_TOKEN_LAPTOP
      # No `scope:` ⇒ READ-ONLY (list_*, read_chat) across all projects.
```

**4. Copy it into the data volume and restart.** Config is read at boot, not
hot-reloaded:

```sh
docker compose --profile base cp paddock.config.yaml paddock:/data/paddock.config.yaml
docker compose --profile base up -d --force-recreate paddock
docker compose --profile base logs paddock | grep 'management API'
# -> "management API: /mcp enabled (self-authenticated — independent of
#     PADDOCK_AUTH_MODE and of any proxy)"
```

A client whose env var is unset, blank, or under 24 characters is **dropped**
with a warning rather than failing the boot — and if every client drops, `/mcp`
reverts to its unconfigured 404. Missing credentials never open the endpoint up.

### `/mcp` needs TLS — and Docker's loopback publish doesn't count

Paddock **refuses** `/mcp` over plaintext from a non-loopback client: a bearer
token on the wire would be readable in transit. There is a subtlety here that
will bite you if you don't know it.

**This recipe's `127.0.0.1:4000` publish is not loopback from inside the
container.** Docker NATs the connection, so the app sees a peer address of
`172.17.0.1` (the bridge gateway), not `127.0.0.1`. So even from the host
itself:

```sh
curl -X POST http://127.0.0.1:4000/mcp -H "Authorization: Bearer $TOKEN" -d '{}'
# 403 {"error":"https required","code":"insecure_transport", …}
```

That is Paddock working as designed, not a misconfiguration. Two consequences:

- **To smoke-test locally, run curl *inside* the container**, where loopback
  really is loopback:

  ```sh
  docker compose --profile base exec paddock curl -sS -X POST \
    http://127.0.0.1:4000/mcp \
    -H "Authorization: Bearer $PADDOCK_MCP_TOKEN_LAPTOP" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"laptop","version":"1"}}}'
  ```

- **To actually use `/mcp` from another machine, put TLS in front.** Any proxy
  that terminates TLS and forwards `X-Forwarded-Proto: https` satisfies the
  check. [`../auth-basic/`](../auth-basic/) is the ready-made one — it terminates
  TLS, gates the browser UI with Basic Auth, and exempts `/mcp` so your bearer
  token reaches Paddock intact. You want TLS regardless: you are shipping a
  bearer token over the network.

  If you add **any** edge gate of your own, exempt `/mcp` and
  `/.well-known/oauth-protected-resource` from it — and only once you are running
  v0.46.0+, which authenticates `/mcp`. Exempting it on an older build would
  publish an unauthenticated, turn-spawning endpoint.

### Connect a client

```sh
claude mcp add --transport http paddock https://paddock.example.com/mcp \
  --header "Authorization: Bearer $PADDOCK_MCP_TOKEN_LAPTOP"
```

### Scopes — read-only by default, writes opt-in

Omit `scope:` and a client gets `list_projects`, `list_chats`, `read_chat`,
`list_triggers` and nothing else. Widen it only deliberately:

```yaml
      scope:
        projects: ["my-project"]        # exact slugs or "*"; deny beats allow
        allow: ["list_*", "read_chat", "send_message"]
        deny: ["create_project"]
```

**`create_chat` / `send_message` / `fork_chat*` / `run_trigger` / `set_trigger`
start keeper turns, and a keeper runs with `Bash` and `Write`.** Granting any of
them is granting code execution on this host; `create_project` clones a
caller-supplied git URL. Paddock logs a loud warning at boot when a client's
scope grants these. Treat such a token exactly like a production secret: one
token per client, scoped to the projects that client needs, revoked by removing
the client from the config and restarting.

**OAuth is not shipped yet.** A static bearer token is the only credential that
works today, so with token-only config
`/.well-known/oauth-protected-resource/mcp` correctly returns **404** — there is
no authorization server to advertise.

## Troubleshooting

- **`curl: (7) Connection refused` right after `up`** — give it a few seconds;
  the healthcheck has a 20s start period. `docker compose ... ps` shows health.
- **Container restart-loops with a `refusing to start` / `SECURITY:` bind
  error** — `PADDOCK_DANGEROUSLY_ALLOW_OPEN` got unset (or forced to `""`). The
  compose sets it to `1` on purpose so the container can boot; see
  [Why it's set](#why-paddock_dangerously_allow_open1-is-set-in-the-compose).
- **Keeper can't push to GitHub** — set `GITHUB_TOKEN` in `.env` and recreate
  the container (`docker compose ... up -d`).
- **`/mcp` returns `404` with a token you believe is right** — `managementApi`
  isn't configured, or every client was dropped for an unset/too-short token.
  Check `docker compose ... logs paddock | grep 'management API'`.
- **`/mcp` returns `403 insecure_transport`** — expected over plain HTTP through
  the loopback publish; Docker's NAT means the container doesn't see a loopback
  peer. See [Remote MCP](#mcp-needs-tls--and-dockers-loopback-publish-doesnt-count).
