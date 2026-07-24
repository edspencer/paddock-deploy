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

## Troubleshooting

- **`curl: (7) Connection refused` right after `up`** — give it a few seconds;
  the healthcheck has a 20s start period. `docker compose ... ps` shows health.
- **Container restart-loops with a `refusing to start` / `SECURITY:` bind
  error** — `PADDOCK_DANGEROUSLY_ALLOW_OPEN` got unset (or forced to `""`). The
  compose sets it to `1` on purpose so the container can boot; see
  [Why it's set](#why-paddock_dangerously_allow_open1-is-set-in-the-compose).
- **Keeper can't push to GitHub** — set `GITHUB_TOKEN` in `.env` and recreate
  the container (`docker compose ... up -d`).
