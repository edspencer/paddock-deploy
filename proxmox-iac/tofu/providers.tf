# ---------------------------------------------------------------------------
# Proxmox provider configuration.
#
# Credentials come from variables (which you set in terraform.tfvars or, better,
# as TF_VAR_* environment variables). Never commit a real endpoint or token —
# terraform.tfvars is gitignored; commit only terraform.tfvars.example.
# ---------------------------------------------------------------------------

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = var.proxmox_tls_insecure

  # The bpg provider uses SSH for a few operations (e.g. uploading files). If
  # you only create containers from a pre-downloaded template you can often skip
  # this, but wiring an SSH agent up front avoids surprises.
  ssh {
    agent = true
  }
}
