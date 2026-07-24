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

> Pin a released version tag (e.g. `:v0.43.0` / `:v0.43.0-devbox`) in production
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

Paddock uses **WebSockets** for live chat. Most ingress controllers proxy them
on the same route with no extra config; raise proxy read/send timeouts if yours
closes idle upgrades early.

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
