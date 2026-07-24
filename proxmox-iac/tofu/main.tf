# ---------------------------------------------------------------------------
# Two Paddock boxes on Proxmox, built from the same reusable LXC module:
#
#   * dev  — more cores/RAM, nesting + keyctl so Docker / the devbox tooling
#            (pm, headless browser, ffmpeg, docker-in-docker) works.
#   * home — lean, no nesting: a plain Paddock instance.
#
# Ansible then configures each one (see ../ansible).
# ---------------------------------------------------------------------------

module "dev_box" {
  source = "./modules/lxc"

  node_name        = var.node_name
  vm_id            = var.dev_vm_id
  hostname         = var.dev_hostname
  template_file_id = var.template_file_id
  datastore_id     = var.datastore_id
  network_bridge   = var.network_bridge
  ssh_public_keys  = var.ssh_public_keys

  cores     = var.dev_cores
  memory    = var.dev_memory
  disk_size = var.dev_disk_size

  # The dev box runs containerised workloads inside an unprivileged LXC.
  nesting = true
  keyctl  = true

  ipv4_address = var.dev_ipv4_address
  ipv4_gateway = var.dev_ipv4_gateway

  tags = ["paddock", "dev"]
}

module "home_box" {
  source = "./modules/lxc"

  node_name        = var.node_name
  vm_id            = var.home_vm_id
  hostname         = var.home_hostname
  template_file_id = var.template_file_id
  datastore_id     = var.datastore_id
  network_bridge   = var.network_bridge
  ssh_public_keys  = var.ssh_public_keys

  cores     = var.home_cores
  memory    = var.home_memory
  disk_size = var.home_disk_size

  # Lean box: no nesting/keyctl.
  nesting = false
  keyctl  = false

  ipv4_address = var.home_ipv4_address
  ipv4_gateway = var.home_ipv4_gateway

  tags = ["paddock", "home"]
}
