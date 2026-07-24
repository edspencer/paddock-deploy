output "dev_box" {
  description = "Dev box identifiers."
  value = {
    vm_id        = module.dev_box.vm_id
    hostname     = module.dev_box.hostname
    ipv4_address = module.dev_box.ipv4_address
  }
}

output "home_box" {
  description = "Home box identifiers."
  value = {
    vm_id        = module.home_box.vm_id
    hostname     = module.home_box.hostname
    ipv4_address = module.home_box.ipv4_address
  }
}
