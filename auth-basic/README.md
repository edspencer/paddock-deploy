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
   and challenges every request for Basic Auth credentials.
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
  things this recipe enforces: the proxy **overwrites** `X-Forwarded-User` on
  every request (so a client can't forge it), and **Paddock is never published**
  (so nothing can bypass the proxy). If you publish Paddock's port or forward the
  client's header through, the model breaks.
- **The bonus:** unlike Tier-3 forward-auth, Basic Auth has **no redirect flow**,
  so it sidesteps the service-worker-vs-SSO-redirect friction the PWA can hit with
  a redirecting IdP. Simple gate, no login-page round-trips.

## Tear down

```bash
docker compose down          # keep the data volume
docker compose down -v       # also delete the Paddock data volume
```
