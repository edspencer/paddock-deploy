# Basic Auth sidecar (Tier 1)

A turnkey **Tier-1** auth recipe: a reverse-proxy **sidecar that does HTTP Basic
Auth over TLS** in front of Paddock. Paddock has no login of its own by design —
authentication lives at the edge — and this is the *simplest* edge you can stand
up without running an SSO identity provider.

Two interchangeable variants, pick one:

- [`caddy/`](./caddy/) — [Caddy](https://caddyserver.com); automatic HTTPS + the
  `basic_auth` directive. Least config.
- [`nginx/`](./nginx/) — [nginx](https://nginx.org); `htpasswd` + a self-signed
  cert you generate. Reach for it if nginx is already your proxy of choice.

## How it works

```
            :443 (TLS + Basic Auth)          private compose network
  client  ───────────────────────►  proxy  ─────────────────────────►  paddock:4000
                                    (caddy /                         (NOT published;
                                     nginx)                           trusted-header mode)
```

1. The **proxy** is the only container with a published port. It terminates TLS
   and challenges every request for Basic Auth credentials — every request
   except `/mcp`, Paddock's Management API, which Paddock authenticates itself.
   See [Remote MCP](#remote-mcp-the-management-api).
2. On success it proxies to **Paddock over a private Compose network** and sets
   `X-Forwarded-User` to the authenticated username, **overwriting** any value the
   client sent (so it can't be forged).
3. **Paddock runs in `trusted-header` mode** (`PADDOCK_AUTH_MODE=trusted-header`,
   `PADDOCK_AUTH_USER_HEADER=X-Forwarded-User`), so `req.user` is that username.
   Provenance and attribution work — requests aren't all "anonymous".
4. **Paddock is never published** (`docker run -p …` is absent from its service),
   so the proxy is the sole ingress.

## Quick start — Caddy

```bash
cd caddy

# 1. Credentials. Generate a bcrypt hash for your password. Pipe through sed to
#    double every "$" → "$$": a bcrypt hash is full of "$", and current Docker
#    Compose interpolates env_file values, so an un-escaped hash gets silently
#    truncated and every login fails.
docker run --rm caddy:2 caddy hash-password --plaintext 'choose-a-password' | sed 's/\$/\$\$/g'
cp caddy.env.example caddy.env
#    → put your username in BASIC_AUTH_USER and the $$-escaped hash in BASIC_AUTH_HASH.

# 2. (Optional) Paddock tokens, so keepers can actually run:
cp paddock.env.example paddock.env      # add CLAUDE_CODE_OAUTH_TOKEN, etc.

# 3. Up.
docker compose up -d

# 4. Try it (self-signed cert locally, so -k):
curl -k https://localhost:8443/api/me                     # 401
curl -k -u admin:choose-a-password https://localhost:8443/api/me   # 200 {"username":"admin"}
```

Open `https://localhost:8443/` in a browser (accept the self-signed warning) and
you'll get a Basic Auth prompt. For a **real public hostname**, set
`SITE_ADDRESS=paddock.example.com` in `caddy.env` and delete the `tls internal`
line in the `Caddyfile` — Caddy then provisions a Let's Encrypt certificate
automatically.

## Quick start — nginx

```bash
cd nginx

# 1. TLS cert (self-signed, for local use):
./gen-certs.sh localhost

# 2. Credentials (prompts for the password; writes ./htpasswd):
./gen-htpasswd.sh admin

# 3. (Optional) Paddock tokens:
cp paddock.env.example paddock.env

# 4. Up.
docker compose up -d

# 5. Try it:
curl -k https://localhost:8443/api/me                     # 401
curl -k -u admin:your-password https://localhost:8443/api/me   # 200 {"username":"admin"}
```

For a real public host, replace the self-signed cert in `certs/` with a
CA-issued one (or just use the Caddy variant, which automates that).

## Configuration

Both variants publish the proxy on host ports **8443** (HTTPS) and **8080**
(HTTP→HTTPS redirect) by default. Override with `HTTPS_PORT` / `HTTP_PORT`.
Pick the image with `PADDOCK_IMAGE` (defaults to
`ghcr.io/edspencer/paddock:latest`; use `:devbox` for the full tooling image).

Files you create (all **gitignored** — never committed):

| Variant | Secret files | How to make them |
| --- | --- | --- |
| caddy | `caddy.env`, `paddock.env` | copy the `.example` files |
| nginx | `htpasswd`, `certs/paddock.*`, `paddock.env` | `gen-htpasswd.sh`, `gen-certs.sh`, copy `.example` |

## Remote MCP (the Management API)

Paddock **v0.46.0+** serves a remote MCP endpoint at **`/mcp`**, so a Claude Code
session on your laptop — or a peer Paddock — can list projects, read chats, and
(if you let it) start turns on this instance.

Both variants here already exempt `/mcp` from Basic Auth. **You still have to
turn the endpoint on**, and until you do it does not exist.

### Why the exemption is necessary

Basic Auth and MCP collide **head-on** over one header. The proxy challenges with
`Authorization`; an MCP client sends `Authorization: Bearer <token>` in the same
header. The proxy reads that bearer token as malformed Basic credentials and
401s, so an MCP client can never reach Paddock through a blanket `basic_auth` —
there is no password it could send that would also be a valid MCP credential.

The same is true of *any* SSO gate (oauth2-proxy, Authelia, Authentik,
Cloudflare Access): those answer an unauthenticated request with a **302 to an
HTML login page**, which no MCP client can follow and which breaks discovery,
since discovery needs a real `401` + `WWW-Authenticate`.

### What still gates it

**Paddock authenticates `/mcp` itself** — with a per-client token, independently
of `PADDOCK_AUTH_MODE` and of this sidecar. The proxy is not what protects it,
and never was. Verified against Paddock 0.46.0 behind both variants:

| Request to `/mcp` | Result |
| --- | --- |
| No management clients configured | **404** — the endpoint does not exist |
| No credential | **401** + `WWW-Authenticate: Bearer realm="paddock"` |
| Wrong bearer token | **401** |
| Valid Basic Auth, no bearer token | **401** — the browser credential buys nothing here |
| Valid bearer token | **200**, MCP session |
| Plaintext from a non-loopback client | **403** `insecure_transport` |

Meanwhile the browser UI is untouched: `GET /api/me` without credentials is
still answered `401 WWW-Authenticate: Basic` by the proxy.

> **⚠️ Deploy order matters.** Only run a version of Paddock that authenticates
> `/mcp` — **v0.46.0 or newer** — with these configs. On an older build nothing
> gates `/mcp` at all, so the exemption would publish an unauthenticated,
> **turn-spawning** endpoint. A spawned keeper has a shell, so **any write scope
> is remote code execution on this host.** Upgrade Paddock first; confirm `/mcp`
> answers `404` or `401` *on its own*; then exempt it at the edge. Paddock's
> fail-closed 404 is a backstop, not a licence to reorder these steps.

### Turning it on

**1. Mint a token, one per client.** The `pdk_<instanceId>_` prefix binds it to
this instance, so a copy is useless at any other Paddock. Minimum 24 characters.

```bash
printf 'pdk_%s_%s\n' myinstance "$(openssl rand -hex 24)"
```

**2. Put it in `paddock.env`** (gitignored) — never in the config file:

```bash
PADDOCK_MCP_TOKEN_LAPTOP=pdk_myinstance_…
```

**3. Declare the client** in Paddock's instance config, at
`/data/paddock.config.yaml` inside the data volume. The credential is a
**reference**, never a literal — an inline `token:` is a hard config error,
because `paddock.config.yaml` is git-tracked and editable from the Settings
screen, so a secret written there leaks the moment it is committed.

```yaml
managementApi:
  instanceId: myinstance
  # The canonical public origin, no trailing slash. Required, and it must be
  # what clients actually type: discovery compares it byte-for-byte, and it
  # cannot be derived from the Host header (a TLS-terminating proxy makes the
  # scheme wrong, and the header is attacker-controlled anyway).
  publicUrl: https://paddock.example.com
  clients:
    laptop:
      auth:
        type: token
        ref: env:PADDOCK_MCP_TOKEN_LAPTOP
      # No `scope:` ⇒ READ-ONLY (list_*, read_chat) across all projects. That
      # default is the safe one; see "Scopes" below before widening it.
```

Copy it into the volume and restart — config is read at boot, not hot-reloaded:

```bash
docker compose cp paddock.config.yaml paddock:/data/paddock.config.yaml
docker compose up -d --force-recreate paddock
docker compose logs paddock | grep 'management API'
# -> "management API: /mcp enabled (self-authenticated — independent of
#     PADDOCK_AUTH_MODE and of any proxy)"
```

A client whose env var is unset, blank, or under 24 characters is **dropped**
with a warning rather than failing the boot — and if every client drops, `/mcp`
reverts to its unconfigured 404. Missing credentials never open the endpoint up.

### Verify

```bash
# The browser UI is still challenged by the proxy:
curl -k -o /dev/null -w '%{http_code}\n' https://localhost:8443/api/me     # 401

# /mcp reaches Paddock, and Paddock is the one challenging:
curl -k -i -X POST https://localhost:8443/mcp -d '{}' | head -2
#   HTTP/1.1 401 Unauthorized
#   www-authenticate: Bearer realm="paddock"      <- Bearer, not Basic

# With the token, a real MCP handshake:
curl -k -X POST https://localhost:8443/mcp \
  -H "Authorization: Bearer $PADDOCK_MCP_TOKEN_LAPTOP" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"laptop","version":"1"}}}'
# -> {"result":{"protocolVersion":"2025-11-25", … "serverInfo":{"name":"paddock", …}}}
```

If the `401` says `Basic` rather than `Bearer`, the request never reached
Paddock — the exemption isn't matching your path. If you get `404` with a token
you believe is right, `managementApi` isn't configured (or every client was
dropped); check the boot logs.

Then point Claude Code at it:

```bash
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
the client from the config (and restarting).

### TLS is not optional here either

Paddock **refuses** `/mcp` over plaintext from a non-loopback client — a bearer
token on the wire is readable in transit. Both variants terminate TLS and
forward `X-Forwarded-Proto: https`, which is what satisfies that check, so this
works out of the box. It is also why `publicUrl` must be `https://` for any
non-loopback host.

### Not yet: OAuth

The only credential that works today is a **static bearer token**. OAuth
(dynamic client registration, browser consent) is planned but not shipped, so
with token-only config `/.well-known/oauth-protected-resource/mcp` correctly
returns **404** — there is no authorization server to advertise, and the MCP spec
requires the document to name one. The configs here exempt that path anyway, so
discovery starts working the day OAuth lands without another edge change.

## Caveats — read these honestly

- **HTTPS is mandatory.** Basic Auth is just a base64-encoded `user:password`
  header sent on **every** request — TLS is the only thing protecting it. Never
  run this over plain HTTP. Both variants terminate TLS and redirect HTTP→HTTPS.
- **It's a gate, not SSO.** One shared static credential, re-sent every request.
  There is **no MFA, no logout, no account lockout, no per-user password reset.**
  It's fine for a solo user or a small trusted LAN behind a quick gate; it is not
  how you'd protect anything shared or internet-exposed. For that, step up to
  **Tier 2** (Cloudflare Access) or **Tier 3** (Authentik/Authelia) — see the
  [Securing guide](https://paddock.edspencer.net/guides/securing/).
- **`trusted-header` is only as safe as the proxy.** The security rests on two
  things this recipe enforces: the proxy is the **only** source of
  `X-Forwarded-User` (it overwrites the header with the authenticated user on
  the challenged paths, and **deletes** it outright on the Basic-Auth-exempt
  `/mcp` paths, where there is no authenticated user to assert), and **Paddock
  is never published** (so nothing can bypass the proxy). If you publish
  Paddock's port or forward the client's header through, the model breaks.
  - The nginx variant routes that value through a `$forwarded_user` variable
    rather than using `$remote_user` directly, and that indirection is
    load-bearing: nginx computes `$remote_user` by **parsing** the
    `Authorization` header, not from the auth_basic module, so under
    `auth_basic off` it still resolves — to whatever unverified username the
    client supplied. Without the reset, `curl -u evil:whatever …/mcp` reaches
    the upstream as `X-Forwarded-User: evil`.
- **The bonus:** unlike Tier-3 forward-auth, Basic Auth has **no redirect flow**,
  so it sidesteps the service-worker-vs-SSO-redirect friction the PWA can hit with
  a redirecting IdP. Simple gate, no login-page round-trips.

## Tear down

```bash
docker compose down          # keep the data volume
docker compose down -v       # also delete the Paddock data volume
```
