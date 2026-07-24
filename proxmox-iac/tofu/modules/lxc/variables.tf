# ---------------------------------------------------------------------------
# Inputs for the reusable LXC container module.
# ---------------------------------------------------------------------------

variable "node_name" {
  type        = string
  description = "Proxmox node to create the container on (e.g. \"pve\")."
}

variable "vm_id" {
  type        = number
  description = "Numeric container ID (CTID). Must be unique on the node."
}

variable "hostname" {
  type        = string
  description = "Hostname set inside the container."
}

variable "template_file_id" {
  type        = string
  description = <<-EOT
    Datastore volume ID of the Debian LXC template, e.g.
    "local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst". Download it once on
    the node with `pveam` (see the README).
  EOT
}

variable "cores" {
  type        = number
  description = "vCPU cores."
  default     = 2
}

variable "memory" {
  type        = number
  description = "Dedicated RAM in MiB."
  default     = 2048
}

variable "swap" {
  type        = number
  description = "Swap in MiB."
  default     = 512
}

variable "disk_size" {
  type        = number
  description = "Root filesystem size in GiB."
  default     = 20
}

variable "datastore_id" {
  type        = string
  description = "Datastore for the root filesystem (e.g. \"local-lvm\")."
  default     = "local-lvm"
}

variable "unprivileged" {
  type        = bool
  description = "Run the container unprivileged. Keep this true."
  default     = true
}

variable "nesting" {
  type        = bool
  description = <<-EOT
    Enable the `nesting` feature. Required for the dev box so Docker/devbox
    tooling works inside the (unprivileged) container. Leave off for lean boxes.
  EOT
  default     = false
}

variable "keyctl" {
  type        = bool
  description = <<-EOT
    Enable the `keyctl` feature. Needed alongside nesting for some containerised
    workloads inside an unprivileged LXC.
  EOT
  default     = false
}

variable "start_on_boot" {
  type        = bool
  description = "Start the container when the node boots."
  default     = true
}

variable "network_bridge" {
  type        = string
  description = "Bridge the container's eth0 attaches to."
  default     = "vmbr0"
}

variable "ipv4_address" {
  type        = string
  description = "IPv4 config: either \"dhcp\" or a CIDR like \"192.0.2.10/24\"."
  default     = "dhcp"
}

variable "ipv4_gateway" {
  type        = string
  description = "IPv4 gateway (only used with a static ipv4_address; null for DHCP)."
  default     = null
}

variable "ssh_public_keys" {
  type        = list(string)
  description = "SSH public keys authorised for the container's root user."
  default     = []
}

variable "root_password" {
  type        = string
  description = <<-EOT
    Optional root password. Prefer SSH keys; leave null to disable password
    login. Marked sensitive.
  EOT
  default     = null
  sensitive   = true
}

variable "tags" {
  type        = list(string)
  description = "Proxmox tags applied to the container."
  default     = []
}
