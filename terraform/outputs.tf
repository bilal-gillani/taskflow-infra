# ---------------------------------------------------------------------------
# Outputs consumed by the Ansible dynamic inventory script and GitHub Actions
# ---------------------------------------------------------------------------

output "app_vm_public_ip" {
  description = "Public IP of the App VM — used by GitHub Actions SSH deploy and Ansible inventory"
  value       = azurerm_public_ip.app_pip.ip_address
}

output "db_vm_private_ip" {
  description = "Private IP of the DB VM — passed to Ansible as db_host"
  value       = azurerm_network_interface.db_nic.private_ip_address
}

output "app_ssh" {
  description = "SSH command for manual access to the App VM"
  value       = "ssh -i ~/.ssh/az-vm-ssh ${var.admin_username}@${azurerm_public_ip.app_pip.ip_address}"
}

output "app_public_url" {
  description = "Public URL of the deployed TaskFlow application"
  value       = "http://${azurerm_public_ip.app_pip.ip_address}/taskflow/index.php"
}
