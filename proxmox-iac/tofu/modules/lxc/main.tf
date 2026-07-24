# ---------------------------------------------------------------------------
# A single unprivileged Debian LXC container on Proxmox.
#
# Deliberately small: one container, sane defaults, and the handful of knobs
# the two Paddock boxes actually differ on (size + the nesting/keyctl features
# the dev box needs for Docker-in-LXC).
# ---------------------------------------------------------------------------

resource "proxmox_virtual_environment_container" "this" {
  node_name     = var.node_name
  vm_id         = var.vm_id
  unprivileged  = var.unprivileged
  start_on_boot = var.start_on_boot
  tags          = var.tags

  # nesting/keyctl let Docker & friends run inside an unprivileged container.
  features {
    nesting = var.nesting
    keyctl  = var.keyctl
  }

  cpu {
    cores = var.cores
  }

  memory {
    dedicated = var.memory
    swap      = var.swap
  }

  disk {
    datastore_id = var.datastore_id
    size         = var.disk_size
  }

  operating_system {
    template_file_id = var.template_file_id
    type             = "debian"
  }

  initialization {
    hostname = var.hostname

    ip_config {
      ipv4 {
        address = var.ipv4_address
        gateway = var.ipv4_gateway
      }
    }

    user_account {
      keys     = var.ssh_public_keys
      password = var.root_password
    }
  }

  network_interface {
    name   = "eth0"
    bridge = var.network_bridge
  }
}
