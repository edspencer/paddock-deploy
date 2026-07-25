# paddock-deploy

Deployment recipes for self-hosting [**Paddock**](https://paddock.edspencer.net) —
the keeper-agent platform. This is the one place to clone to stand up your own
instance. Pick the recipe that matches where you want to run it.

> New to Paddock? Start with the docs at **https://paddock.edspencer.net**.

## Which recipe should I use?

| You want to run Paddock on… | Use | Status |
| --- | --- | --- |
| A single VM or LXC container, with Docker | [`docker/`](./docker/) | ✅ ready |
| Proxmox, as reproducible infra-as-code (dev box + home box, Tofu + Ansible) | [`proxmox-iac/`](./proxmox-iac/) | recipe in [#411](https://github.com/edspencer/paddock/issues/411) |
| A Kubernetes cluster | [`kubernetes/`](./kubernetes/) | ✅ available |

**Not sure?** If you just want it running on one host, start with
[`docker/`](./docker/) — it's the simplest path and everything else builds on
the same images.

### …and what goes in front of it?

That table picks *where* Paddock runs. This one picks what it's reachable
**through** — route by what you need, not by the directory name:

| You need… | Use | What it gives you |
| --- | --- | --- |
| Just to run it, reachable from the host | [`docker/`](./docker/) on its own | Loopback publish. No proxy, nothing extra to configure. |
| **HTTPS** — including to reach `/mcp` from another machine | [`auth-basic/`](./auth-basic/) | A **TLS front door** (Caddy provisions certs automatically), with `/mcp` already exempted. |
| A password gate on the browser UI as well | [`auth-basic/`](./auth-basic/) | Same recipe — the front door also challenges the UI for Basic Auth credentials. |
| SSO, MFA, real user accounts | Your own proxy | oauth2-proxy / Authelia / Authentik / Cloudflare Access. Exempt `/mcp` from it — see below. |

> [`auth-basic/`](./auth-basic/) is named for its browser gate, but the part most
> people come for is **TLS termination**. If you want to reach `/mcp` from
> another machine, that is the recipe you want — Paddock refuses `/mcp` over
> plaintext from a non-loopback client, so remote MCP needs HTTPS regardless of
> whether you care about the password gate.

## Base vs. devbox images

Paddock ships two official images. All recipes let you pick either one.

| Image | Contains | Use when |
| --- | --- | --- |
| `ghcr.io/edspencer/paddock:latest` | The Paddock app plus `git`, `gh`, and the `claude` CLI. | Your agents mostly read, write, and reason over text and code. |
| `ghcr.io/edspencer/paddock:devbox` | Everything in base, plus the **software-engineering box** tooling: `pm` (a PM2-based wrapper for stable-port preview servers), `ffmpeg`, the Playwright MCP browser (headless Chromium), and the Docker CLI (for docker-in-docker workflows). | Your agents build and run apps — spinning up dev/preview servers, driving a browser, transcoding media, or building containers. |

The **devbox** image only adds *tools*. The conventions for how agents use those
tools (for example, "run preview servers under `pm`") live in an instance-wide
`CLAUDE.md` that you mount into the data volume — never baked into an image. See
[`CLAUDE.md.example`](./CLAUDE.md.example) for a generic starter you can drop in
and adapt.

## The three layers

Every recipe here keeps three concerns decoupled:

1. **App + capabilities** → the image (base or devbox). Immutable, versioned.
2. **Composition** → a thin compose file / overlay: which instances run, branding,
   env, and secrets.
3. **Data + operator context** → the mounted data volume, including your
   instance-wide `CLAUDE.md`. Nothing from this layer goes into an image.

## Repository layout

```
docker/          # Docker on a single VM or LXC              (#410)
proxmox-iac/     # Proxmox infra-as-code: Tofu + Ansible     (#411)
kubernetes/      # Kubernetes manifests / Helm               (#412)
auth-basic/      # TLS front door (Caddy / nginx) + Basic Auth gate  (#434)
CLAUDE.md.example  # generic starter instance-wide CLAUDE.md
LICENSE          # MIT
```

## Security note

Paddock has **no built-in password auth** — authenticate at the edge with a
reverse proxy or auth sidecar (nginx, oauth2-proxy, Authelia, Cloudflare Access,
…). Paddock binds to loopback by default and refuses to start open (non-loopback)
with authentication disabled. Read the **Securing Paddock** guide at
https://paddock.edspencer.net before exposing an instance to a network.

Want the simplest turnkey front door? [`auth-basic/`](./auth-basic/) stands up a
Caddy or nginx sidecar that **terminates TLS and gates the browser UI with Basic
Auth** (Tier 1 in the Securing guide's ladder) — no SSO required. Reach for it
whenever Paddock needs to be reachable over a network, including for remote
`/mcp`, which requires HTTPS.

## Two auth surfaces, not one

That ladder is about **the browser UI**, and it is only half the picture. From
**v0.46.0** Paddock also serves a remote MCP endpoint at **`/mcp`** — the
Management API — so a Claude Code session on your laptop, or a peer Paddock, can
drive an instance. It has its **own** authentication, and the two are
**orthogonal**:

| | Browser UI (`/`, `/api/*`) | Management API (`/mcp`) |
| --- | --- | --- |
| Who authenticates | Your edge (proxy / SSO / Basic Auth), or `PADDOCK_AUTH_MODE` | **Paddock itself**, always |
| Credential | Whatever your tier uses (password, SSO session, JWT) | A per-client bearer token |
| Closed by default | You choose the tier | Yes — **404** until you configure a client |

**Every tier of the ladder keeps working**, because moving up it changes only who
guards the browser UI. `/mcp` is authenticated by Paddock at every tier,
including Tier 0 (`PADDOCK_AUTH_MODE=none`, bare on loopback): **a proxy is never
a prerequisite** for a gated `/mcp`. The [`docker/`](./docker/) recipe is the
reference for exactly that — no proxy at all, and `/mcp` is still gated.

The catch runs the other way. **Any auth gate at the edge breaks MCP unless you
exempt `/mcp` from it**, because the edge and the MCP client fight over the same
header (Basic Auth) or answer with an un-followable HTML login redirect (any SSO
proxy). Every recipe here that has an edge gate now carries that exemption —
along with `/.well-known/oauth-protected-resource`, which clients probe before
they hold any credential:

| Recipe | Where the exemption lives |
| --- | --- |
| [`auth-basic/caddy`](./auth-basic/caddy/) | `Caddyfile` — a `handle` block outside `basic_auth` |
| [`auth-basic/nginx`](./auth-basic/nginx/) | `nginx.conf` — `auth_basic off` locations |
| [`kubernetes/`](./kubernetes/) | `ingress-mcp.yaml` — a second, un-annotated Ingress |
| [`docker/`](./docker/) | n/a — no edge to exempt |

> **⚠️ Order of operations.** Apply an edge exemption only *after* you are
> running a Paddock that authenticates `/mcp` (**v0.46.0+**). On an older build
> nothing gates `/mcp`, so exempting it would publish an unauthenticated,
> **turn-spawning** endpoint — and keepers run with shell access, so **any write
> scope is effectively remote code execution on the host**. That is also why the
> Management API defaults to **read-only** scope, requires TLS, and takes its
> tokens **by reference** (an inline token in the config file is a hard error).

Today the only working credential is a **static bearer token**; OAuth is planned
but not shipped. Each recipe's README has the full setup.

## License

[MIT](./LICENSE) © Ed Spencer.
