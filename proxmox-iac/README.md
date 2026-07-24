# Proxmox infra-as-code recipe

Stand up Paddock on Proxmox as reproducible infrastructure-as-code — a dev box
and a home box — using OpenTofu (Terraform) to provision and Ansible to
configure.

> 🚧 **Recipe coming in [#411](https://github.com/edspencer/paddock/issues/411).**

This directory will hold the Tofu configuration (LXC containers on Proxmox) and
Ansible playbooks that install the Paddock image, an auth sidecar, and the
mounted data volume for your instance-wide `CLAUDE.md` (see
[`../CLAUDE.md.example`](../CLAUDE.md.example)).

For now, see the deployment docs at **https://paddock.edspencer.net**.
