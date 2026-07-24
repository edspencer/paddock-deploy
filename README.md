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
| A Kubernetes cluster | [`kubernetes/`](./kubernetes/) | recipe in [#412](https://github.com/edspencer/paddock/issues/412) |

**Not sure?** If you just want it running on one host, start with
[`docker/`](./docker/) — it's the simplest path and everything else builds on
the same images.

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
CLAUDE.md.example  # generic starter instance-wide CLAUDE.md
LICENSE          # MIT
```

## Security note

Paddock has **no built-in password auth** — authenticate at the edge with a
reverse proxy or auth sidecar (nginx, oauth2-proxy, Authelia, Cloudflare Access,
…). Paddock binds to loopback by default and refuses to start open (non-loopback)
with authentication disabled. Read the **Securing Paddock** guide at
https://paddock.edspencer.net before exposing an instance to a network.

## License

[MIT](./LICENSE) © Ed Spencer.
