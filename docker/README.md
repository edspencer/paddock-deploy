# Docker recipe

Run Paddock with Docker on a single VM or LXC container — the simplest way to
self-host.

> 🚧 **Recipe coming in [#410](https://github.com/edspencer/paddock/issues/410).**

This directory will hold a `compose.yaml` and supporting files for running either
image:

- `ghcr.io/edspencer/paddock:latest` — base (app + `git` / `gh` / `claude`)
- `ghcr.io/edspencer/paddock:devbox` — base + `pm`, `ffmpeg`, headless browser,
  Docker CLI

along with an auth sidecar and a mounted data volume for your instance-wide
`CLAUDE.md` (see [`../CLAUDE.md.example`](../CLAUDE.md.example)).

For now, see the deployment docs at **https://paddock.edspencer.net**.
