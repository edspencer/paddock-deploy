# Kubernetes recipe

Run Paddock on a Kubernetes cluster.

> 🚧 **Recipe coming in [#412](https://github.com/edspencer/paddock/issues/412).**

This directory will hold the Kubernetes manifests (Deployment, Service, Ingress,
and a PersistentVolumeClaim for the data volume) for running either the base or
`devbox` image, fronted by an auth-enabled ingress. Your instance-wide
`CLAUDE.md` (see [`../CLAUDE.md.example`](../CLAUDE.md.example)) lives on the
mounted volume.

For now, see the deployment docs at **https://paddock.edspencer.net**.
