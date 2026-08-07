resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.environment}"
  location = var.location
}

output "name" {
  value       = azurerm_resource_group.rg.name
  description = "Resource Group Name"
}

output "location" {
  value       = azurerm_resource_group.rg.location
  description = "Resource Group Location"
}
