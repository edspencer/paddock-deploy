# Kubernetes recipe

Run Paddock on a Kubernetes cluster using the published images. Plain manifests,
assembled with [Kustomize](https://kustomize.io/) (built into `kubectl`) — no
Helm required.

Paddock is an **app**, not a horizontally-scalable service. This recipe runs
**one** replica against **one** persistent volume, fronted by an auth-enabled
Ingress. Read [Statefulness & single-writer](#statefulness--single-writer)
before you touch `replicas`.

## What's here

| File | Purpose |
| --- | --- |
| `kustomization.yaml` | Assembles the resources below; pins the image tag. |
| `deployment.yaml` | The Paddock pod. `replicas: 1`, `strategy: Recreate`, `/api/health` probes. |
| `service.yaml` | Internal `ClusterIP` on port 80 → container port 4000. |
| `pvc.yaml` | `ReadWriteOnce` claim mounted at `/data` (the stateful bit). |
| `secret.example.yaml` | Template for the Claude / GitHub token Secret. **Never commit real tokens.** |
| `ingress.yaml` | Optional external route. Only safe behind an auth layer. |
| `ingress-mcp.yaml` | Optional. Routes `/mcp` past ingress auth, for the Management API. Read its header before applying. |

## Prerequisites

- A cluster and a `kubectl` context pointing at it.
- A **default StorageClass** (or edit `storageClassName` in `pvc.yaml`). The data
  volume must be **durable** — resume depends on it surviving pod restarts.
- A Claude credential: a `CLAUDE_CODE_OAUTH_TOKEN` (Claude Max, the `cli`
  runtime) **or** an `ANTHROPIC_API_KEY` (the `sdk` runtime, API pricing).

## Quick start

```sh
# 1. A namespace to hold the instance.
kubectl create namespace paddock

# 2. The token Secret. Create it imperatively so tokens never touch a file:
kubectl -n paddock create secret generic paddock-secrets \
  --from-literal=CLAUDE_CODE_OAUTH_TOKEN='sk-...' \
  --from-literal=GITHUB_TOKEN='ghp-...'          # optional, enables git push
# (or copy secret.example.yaml -> secret.yaml, fill it in, and apply it.)

# 3. Deploy.
kubectl -n paddock apply -k .

# 4. Watch it come up (readiness probes /api/health).
kubectl -n paddock rollout status deploy/paddock
```

Reach it without an Ingress by port-forwarding:

```sh
kubectl -n paddock port-forward deploy/paddock 4000:4000
curl -fsS http://127.0.0.1:4000/api/health      # -> {"ok":true}
```

Then wire up [external access](#exposing-paddock).

## Base vs. devbox image

The Deployment uses `ghcr.io/edspencer/paddock:latest` (the **base** image: app
plus `git` / `gh` / `claude`). For the coding-agent toolbox — `pm`, `ffmpeg`, the
headless Playwright browser, the Docker CLI — switch to the **devbox** image by
editing `kustomization.yaml`:

```yaml
images:
  - name: ghcr.io/edspencer/paddock
    newTag: devbox        # was: latest
```

The devbox image is much heavier (the Chromium layer alone is ~1 GB) and wants
more memory — raise the container `resources.limits` in `deployment.yaml`. The
devbox image only adds *tools*; the conventions for using them (e.g. "run preview
servers under `pm`") belong in your instance-wide `CLAUDE.md` on the data volume
(see [`../CLAUDE.md.example`](../CLAUDE.md.example)), never baked into an image.

> Pin a released version tag (e.g. `:0.46.0` / `:0.46.0-devbox`) in production
> rather than the moving `:latest` / `:devbox`.

## Statefulness & single-writer

**`/data` is the instance.** It holds the project store, the generated herdctl
config and state, and — because the image sets `HOME=/data` — the Claude session
transcripts under `~/.claude/projects`. **Resume depends on this volume
persisting.** Lose it and you lose every project and conversation.

Paddock is **single-writer**. Exactly one process may own `/data` at a time. This
recipe enforces that three ways, and you must keep all three:

- **`replicas: 1`.** Do not scale up. To run more Paddocks, deploy separate
  instances with **separate** volumes and namespaces — never two pods on one PVC.
- **`strategy: Recreate`** (not `RollingUpdate`). The old pod fully terminates and
  releases the volume before the new one starts, so a rollout never briefly runs
  two writers. With a `ReadWriteOnce` volume, `RollingUpdate` would also deadlock
  (the new pod can't attach the volume the old one still holds).
- **`ReadWriteOnce` PVC.** A single node mounts it. On a multi-node cluster the
  pod is scheduled to the node holding the volume.

Back up `/data` (volume snapshots, or a scheduled copy) — this recipe does not.

## Exposing Paddock

**Paddock has no built-in authentication.** In a cluster the pod is reachable
from anything that can route to its Service, so do not expose it without an auth
layer in front.

- Keep `service.yaml` as `ClusterIP` (the default here). Don't turn it into a
  `LoadBalancer`/`NodePort` bare.
- Put an authenticating proxy in front: an external auth proxy (oauth2-proxy,
  Authelia, Authentik, Cloudflare Access) or your ingress controller's auth
  middleware. `ingress.yaml` includes the ingress-nginx external-auth annotation
  pattern as a starting point — edit the host, TLS secret, `ingressClassName`,
  and auth URLs for your cluster, then add it to `kustomization.yaml`.
- Alternatively, run Paddock in one of its downstream auth modes
  (`trusted-header` / `jwt`) so it turns an already-authenticated upstream
  identity into a user. Set `PADDOCK_AUTH_MODE` and friends via env in
  `deployment.yaml` (commented examples are there). Health probes are always
  exempt from auth.
- **If you run the Management API**, whatever auth you put at the ingress must
  **exempt `/mcp`** or MCP can never reach Paddock — see
  [Remote MCP](#remote-mcp-the-management-api). That endpoint authenticates
  itself; the browser auth tier above is orthogonal to it and both keep working.

Paddock uses **WebSockets** for live chat. Most ingress controllers proxy them
on the same route with no extra config; raise proxy read/send timeouts if yours
closes idle upgrades early.

## Remote MCP (the Management API)

Paddock **v0.46.0+** serves a remote MCP endpoint at **`/mcp`**, so a Claude Code
session outside the cluster — or a peer Paddock — can list projects, read chats,
and (if you let it) start turns on this instance.

**Paddock authenticates `/mcp` itself**, with a per-client bearer token,
independently of `PADDOCK_AUTH_MODE` and of your ingress. The endpoint fails
closed: **404** when no management clients are configured, **401** +
`WWW-Authenticate` when the credential is missing or wrong, **403** for
plaintext from a non-loopback client. An ingress is never what protects it.

### Exempt `/mcp` from ingress auth

That independence is exactly why an auth layer at the ingress **breaks** MCP
rather than adding to it:

- An **external-auth / SSO proxy** (oauth2-proxy, Authelia, Authentik,
  Cloudflare Access) answers an unauthenticated request with a **302 to an HTML
  login page**. No MCP client can follow that, and discovery needs a real `401` +
  `WWW-Authenticate`.
- **Basic Auth** (`nginx.ingress.kubernetes.io/auth-type: basic`) collides
  head-on: the challenge uses the `Authorization` header, which is exactly where
  an MCP client puts its `Authorization: Bearer <token>`. The proxy reads that
  bearer token as malformed Basic credentials and 401s.

ingress-nginx auth annotations are **per-Ingress-resource, not per-path**, and
there is no "except this path" annotation. So the pattern is a **second Ingress
object on the same host** carrying no auth annotations and the two exempt paths
(`/mcp`, `pathType: Exact`; `/.well-known/oauth-protected-resource`,
`pathType: Prefix`) — its more specific paths win over the gated `path: /`.
That is [`ingress-mcp.yaml`](./ingress-mcp.yaml), which also sketches the
equivalent for Traefik, Gateway API and Cloudflare Access.

It is deliberately **not** in `kustomization.yaml`, so `apply -k .` can't enable
it by accident:

```sh
kubectl -n paddock apply -f ingress-mcp.yaml
```

> **⚠️ Deploy order matters.** Apply the exemption only once the running image
> is **v0.46.0 or newer**. On an older build nothing gates `/mcp` at all, so this
> Ingress would publish an unauthenticated, **turn-spawning** endpoint — and a
> keeper runs with a shell, so **any write scope is remote code execution in your
> cluster**. Roll the image first, confirm `/mcp` answers `404` or `401` on its
> own, then apply. Paddock's fail-closed 404 is a backstop, not a licence to
> reorder these steps.

Also exempt the **`/.well-known/oauth-protected-resource`** prefix, not just
`/mcp`. Clients request the path-inserted form
`/.well-known/oauth-protected-resource/mcp`; if that path is gated or returns
HTML instead of JSON, the client silently falls through to treating Paddock as
its own authorization server, with no error naming the cause.

**TLS is required, not optional.** Paddock refuses `/mcp` over plaintext from a
non-loopback client — a bearer token would be readable in transit. Terminate TLS
at the ingress and make sure `X-Forwarded-Proto: https` is forwarded
(ingress-nginx does by default); that is what satisfies the check.

### Turning it on

**1. Mint a token, one per client** (>= 24 chars; the `pdk_<instanceId>_` prefix
binds it to this instance, so a copy is useless at any other Paddock):

```sh
printf 'pdk_%s_%s\n' myinstance "$(openssl rand -hex 24)"
```

**2. Add it to the Secret** — it reaches the pod via the existing `envFrom`:

```sh
kubectl -n paddock create secret generic paddock-secrets \
  --from-literal=CLAUDE_CODE_OAUTH_TOKEN='sk-...' \
  --from-literal=PADDOCK_MCP_TOKEN_LAPTOP='pdk_myinstance_...' \
  --dry-run=client -o yaml | kubectl apply -f -
```

**3. Declare the client** in `paddock.config.yaml` on the data volume. The
credential is a **reference**, never a literal — an inline `token:` is a hard
config error, because `paddock.config.yaml` is git-tracked and editable from the
Settings screen, so a secret written there would leak the moment it was
committed.

```yaml
managementApi:
  instanceId: myinstance
  # The canonical public origin, no trailing slash. Required, and it must match
  # your Ingress host — discovery compares it byte-for-byte, and it cannot be
  # derived from the Host header behind a TLS-terminating ingress.
  publicUrl: https://paddock.example.com
  clients:
    laptop:
      auth:
        type: token
        ref: env:PADDOCK_MCP_TOKEN_LAPTOP
      # No `scope:` ⇒ READ-ONLY (list_*, read_chat) across all projects.
```

Write it into the PVC and restart — config is read at boot, not hot-reloaded:

```sh
kubectl -n paddock cp paddock.config.yaml "$(kubectl -n paddock get pod \
  -l app.kubernetes.io/name=paddock -o name | cut -d/ -f2)":/data/paddock.config.yaml
kubectl -n paddock rollout restart deploy/paddock
kubectl -n paddock logs deploy/paddock | grep 'management API'
# -> "management API: /mcp enabled (self-authenticated — independent of
#     PADDOCK_AUTH_MODE and of any proxy)"
```

A ConfigMap mounted with `subPath` works too, but it lands read-only, so the
Settings screen can no longer edit the instance config. Prefer writing into the
volume unless you manage all config as code.

A client whose env var is unset, blank, or under 24 characters is **dropped**
with a warning rather than failing the boot — and if every client drops, `/mcp`
reverts to its unconfigured 404. Missing credentials never open the endpoint up.

Then point a client at it:

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
them is granting code execution in your cluster; `create_project` clones a
caller-supplied git URL. Paddock logs a loud warning at boot when a client's
scope grants these. One token per client, scoped to the projects that client
needs; revoke by removing the client from the config and restarting.

**OAuth is not shipped yet.** A static bearer token is the only credential that
works today, so with token-only config
`/.well-known/oauth-protected-resource/mcp` correctly returns **404** — there is
no authorization server to advertise. Exempting the path now means discovery
starts working the day OAuth lands, without another ingress change.

## Configuration

Runtime config is via environment variables (`deployment.yaml`). `PORT` (4000),
`HOST` (`0.0.0.0`), `PADDOCK_DATA_DIR` / `HOME` (`/data`) are already set in the
image and restated here for clarity. Common additions: `PADDOCK_AUTH_MODE`,
`PADDOCK_BRAND_NAME`, `PADDOCK_KEEPER_DRIVE_MODE`. See the deployment docs at
<https://paddock.edspencer.net> for the full reference.

## Private image pull

`ghcr.io/edspencer/paddock` is published publicly. If your cluster can't pull it
(e.g. you mirror it to a private registry), create a pull secret and reference it
in `deployment.yaml`:

```sh
kubectl -n paddock create secret docker-registry ghcr-pull \
  --docker-server=ghcr.io \
  --docker-username='<user>' \
  --docker-password='<token>'
```

```yaml
# deployment.yaml, under spec.template.spec:
imagePullSecrets:
  - name: ghcr-pull
```

## Verified on a cluster

This recipe was deployed to a real k3s cluster (`local-path` default
StorageClass) and checked end to end:

- `kubectl apply -k .` created the Service, PVC (bound, 10Gi, RWO, `local-path`),
  and Deployment; the pod reached `1/1 Ready` via the `/api/health` readiness
  probe.
- `curl http://127.0.0.1:4000/api/health` (in-pod) returned `{"ok":true}`, and
  the app populated `/data` on first boot (`projects/`, `.claude/`, `.herdctl/`,
  `herdctl.yaml`, `attachments/`, `scratch/`).
- **Data survival:** wrote a marker file into `/data`, `kubectl delete pod`'d the
  Paddock pod, and the Deployment rescheduled a fresh pod. The marker — and the
  whole `/data` tree — was intact on the new pod, which came back healthy. The
  PVC decouples instance state from pod lifecycle exactly as intended.

## Cleanup

```sh
kubectl -n paddock delete -k .
kubectl -n paddock delete secret paddock-secrets
kubectl -n paddock delete pvc paddock-data     # deletes the data volume
kubectl delete namespace paddock
```
