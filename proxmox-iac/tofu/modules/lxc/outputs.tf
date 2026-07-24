output "vm_id" {
  description = "Container ID (CTID)."
  value       = proxmox_virtual_environment_container.this.vm_id
}

output "hostname" {
  description = "Container hostname."
  value       = var.hostname
}

output "ipv4_address" {
  description = <<-EOT
    The configured IPv4 address string. With "dhcp" this is literally "dhcp" —
    query the running container (or your DHCP server) for the leased address.
  EOT
  value       = var.ipv4_address
}
