# Proxmox infra-as-code recipe

Stand up Paddock on Proxmox as reproducible infrastructure-as-code: **two
unprivileged Debian LXCs** — a **dev box** and a **home box** — provisioned with
[OpenTofu](https://opentofu.org) (a Terraform fork) and configured with
[Ansible](https://docs.ansible.com).

This is a clean-room, sanitized distillation of how the project is actually run.
Everything host-, secret-, and network-specific is a **placeholder** you fill in.

## The two boxes

| Box | Sizing (default) | Extra features | Tooling installed |
| --- | --- | --- | --- |
| **dev** | 4 cores / 8 GiB / 40 GiB | `nesting=1`, `keyctl=1` (so Docker & the devbox tools work inside an unprivileged LXC) | Node, `gh`, `claude`, **plus** PM2, `ffmpeg`, headless Chromium (Playwright MCP), Docker Engine |
| **home** | 2 cores / 2 GiB / 20 GiB | none (lean) | Node, `gh`, `claude` |

Both run Paddock bound to loopback; you authenticate at the edge (reverse proxy
or auth sidecar) — Paddock ships no built-in password auth. See the repo-root
[README](../README.md#security-note).

## Layout

```
proxmox-iac/
├── tofu/                      # provision: two LXCs from one reusable module
│   ├── modules/lxc/           #   reusable single-container module
│   ├── main.tf                #   dev_box + home_box from the module
│   ├── variables.tf           #   sizing / network / credential inputs
│   ├── providers.tf           #   bpg/proxmox provider config
│   ├── versions.tf            #   version pins
│   └── terraform.tfvars.example
└── ansible/                   # configure: install tooling + deploy Paddock
    ├── site.yml               #   plays the `paddock` role over both boxes
    ├── group_vars/{dev,home}.yml
    ├── inventory/hosts.ini.example
    ├── secrets.example.env    #   documented secret-file pattern
    └── roles/paddock/         #   common + devbox + config + deploy tasks
```

## Prerequisites

- A **Proxmox VE** node you can reach over its API.
- A Proxmox **API token** with permission to create containers. Create a least-
  privilege token (e.g. a `paddock@pve` user with a `tofu` token) rather than
  reusing root.
- A **Debian LXC template** downloaded on the node:
  ```
  pveam update
  pveam download local debian-12-standard_12.7-1_amd64.tar.zst
  ```
- Locally: **OpenTofu ≥ 1.6** (or Terraform), **Ansible** (core ≥ 2.15), and an
  **SSH key** whose public half you list in `terraform.tfvars` (Ansible connects
  over it).

## 1. Provision with Tofu

```bash
cd tofu
cp terraform.tfvars.example terraform.tfvars   # then edit — placeholders only!
tofu init
tofu apply
tofu output          # prints the dev/home CTIDs and configured addresses
```

`terraform.tfvars` (and Tofu state) are gitignored — never commit your endpoint,
token, or state. You can pass any variable as `TF_VAR_*` instead of the file.

This creates the two containers. If you used `dhcp`, look up each box's leased
address (from your DHCP server or `pct exec <ctid> -- ip a`); if you set static
CIDRs, you already know them.

## 2. Configure with Ansible

```bash
cd ../ansible
ansible-galaxy collection install -r requirements.yml   # community.general/docker

cp inventory/hosts.ini.example inventory/hosts.ini      # set the real addresses
cp secrets.example.env secrets.env                      # fill in GH_TOKEN etc.

ansible-playbook site.yml                # configure both boxes
# ansible-playbook site.yml --limit dev  # or one at a time
```

`hosts.ini` and `secrets.env` are gitignored.

The role:

1. **Common (both boxes)** — installs Node (NodeSource), `gh` (GitHub CLI apt
   repo), and the `claude` CLI (npm global); creates the `paddock` service user
   and the `/opt/paddock` + `/var/lib/paddock` layout.
2. **Dev box only** — installs PM2, `ffmpeg`, headless Chromium (for the
   Playwright MCP), and Docker Engine, and adds `paddock` to the `docker` group.
3. **Config** — writes the base env file and copies your `secrets.env` to a
   mode-`0600` `paddock.secret.env`.
4. **Deploy** — see below.

## Deploy method: tarball + systemd (primary) or Docker image

The role supports two ways to run Paddock, chosen with `paddock_deploy_method`:

- **`tarball` (default / primary)** — extracts a release tarball to
  `/opt/paddock` and runs it with the host's Node under a `paddock.service`
  systemd unit. Keeper agents use the **host-installed** `claude`/`gh` (and, on
  the dev box, PM2/ffmpeg/browser/Docker). Set `paddock_release_url` to the
  release artifact you want and `paddock_entrypoint` to its entry file.
- **`docker` (alternative)** — runs the official image
  (`ghcr.io/edspencer/paddock:latest` on home, `:devbox` on dev) under a systemd
  unit. Simpler — the tools are baked into the image — but Paddock runs inside a
  container rather than directly on the box. Enable with
  `-e paddock_deploy_method=docker` (dev box already has Docker; on the home box
  also pass `-e paddock_install_docker=true`).

Both write `paddock.service`; switch by re-running with the other value.

## Secrets

There is **no secrets manager and no SSH-CA** in this recipe — deliberately. The
only mechanism is a plain, operator-managed env file: copy
[`ansible/secrets.example.env`](./ansible/secrets.example.env) to `secrets.env`,
fill it in, and Ansible installs it as a mode-`0600` `EnvironmentFile`. Swap in
Vault / SOPS / sealed files if you need something richer.

## Verify

After `ansible-playbook`, each box should answer its health check:

```bash
curl -fsS http://127.0.0.1:3000/api/health     # run on the box (loopback bind)
systemctl status paddock
```

Confirm the split: the **dev** box has `pm2`, `ffmpeg`, `chromium`, and `docker`
on `PATH`; the **home** box has only `node`, `gh`, and `claude`.

## What's verified vs. deferred

The Tofu and the Ansible config half are checked locally: `tofu validate`,
`ansible-lint`, `ansible-playbook --syntax-check`, and the role run end-to-end
against a throwaway Debian container. The **live `tofu apply` against a real
Proxmox node** (and therefore the first real container boot + `/api/health`) is
**deferred to a human operator** — no Proxmox is available in the build
environment.
