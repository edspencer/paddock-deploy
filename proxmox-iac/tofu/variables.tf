# ---------------------------------------------------------------------------
# Root inputs. Fill these in via terraform.tfvars (copy the .example) or
# TF_VAR_* environment variables. Secrets are marked sensitive.
# ---------------------------------------------------------------------------

# --- Proxmox connection ----------------------------------------------------

variable "proxmox_endpoint" {
  type        = string
  description = "Proxmox API URL, e.g. \"https://proxmox.example.com:8006/\"."
}

variable "proxmox_api_token" {
  type        = string
  description = <<-EOT
    Proxmox API token in "user@realm!tokenid=uuid" form. Create a dedicated
    token with least privilege (see the README). Marked sensitive.
  EOT
  sensitive   = true
}

variable "proxmox_tls_insecure" {
  type        = bool
  description = "Skip TLS verification (only for a self-signed lab cert)."
  default     = false
}

variable "node_name" {
  type        = string
  description = "Proxmox node the containers are created on."
  default     = "pve"
}

# --- Shared container settings ---------------------------------------------

variable "template_file_id" {
  type        = string
  description = <<-EOT
    Datastore volume ID of the Debian LXC template, e.g.
    "local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst".
  EOT
}

variable "datastore_id" {
  type        = string
  description = "Datastore for container root filesystems."
  default     = "local-lvm"
}

variable "network_bridge" {
  type        = string
  description = "Bridge the containers attach to."
  default     = "vmbr0"
}

variable "ssh_public_keys" {
  type        = list(string)
  description = "SSH public keys authorised on both containers' root user."
  default     = []
}

# --- Dev box ---------------------------------------------------------------

variable "dev_keyctl" {
  type        = bool
  description = <<-EOT
    Enable the LXC `keyctl` feature on the dev box. Docker works on current
    kernels with `nesting` alone, so this defaults to false. Leave it false
    unless a workload truly needs the kernel keyring: Proxmox restricts setting
    keyctl to the REAL root@pam user, and an API token — even one belonging to
    root@pam — is rejected ("changing feature flags (except nesting) is only
    allowed for root@pam"). So a token-authenticated `tofu apply` cannot set it;
    you'd have to authenticate the provider as root@pam via username+password,
    or set it out of band (`pct set <id> --features nesting=1,keyctl=1` as root)
    and add `lifecycle { ignore_changes = [features] }`.
  EOT
  default     = false
}

variable "dev_vm_id" {
  type        = number
  description = "CTID for the dev box."
  default     = 130
}

variable "dev_hostname" {
  type        = string
  description = "Hostname for the dev box."
  default     = "paddock-dev"
}

variable "dev_cores" {
  type        = number
  description = "vCPU cores for the dev box (sized for builds + browsers)."
  default     = 4
}

variable "dev_memory" {
  type        = number
  description = "RAM (MiB) for the dev box."
  default     = 8192
}

variable "dev_disk_size" {
  type        = number
  description = "Root disk (GiB) for the dev box."
  default     = 40
}

variable "dev_ipv4_address" {
  type        = string
  description = "\"dhcp\" or a static CIDR for the dev box."
  default     = "dhcp"
}

variable "dev_ipv4_gateway" {
  type        = string
  description = "Gateway for a static dev-box address (null with dhcp)."
  default     = null
}

# --- Home box --------------------------------------------------------------

variable "home_vm_id" {
  type        = number
  description = "CTID for the home box."
  default     = 131
}

variable "home_hostname" {
  type        = string
  description = "Hostname for the home box."
  default     = "paddock-home"
}

variable "home_cores" {
  type        = number
  description = "vCPU cores for the lean home box."
  default     = 2
}

variable "home_memory" {
  type        = number
  description = "RAM (MiB) for the home box."
  default     = 2048
}

variable "home_disk_size" {
  type        = number
  description = "Root disk (GiB) for the home box."
  default     = 20
}

variable "home_ipv4_address" {
  type        = string
  description = "\"dhcp\" or a static CIDR for the home box."
  default     = "dhcp"
}

variable "home_ipv4_gateway" {
  type        = string
  description = "Gateway for a static home-box address (null with dhcp)."
  default     = null
}
