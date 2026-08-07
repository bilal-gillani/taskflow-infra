resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.address_space
}

resource "azurerm_subnet" "subnets" {
  for_each             = var.subnets
  name                 = "subnet-${var.environment}-${each.key}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = each.value.address_prefixes

  depends_on = [azurerm_virtual_network.vnet]
}

resource "azurerm_subnet_network_security_group_association" "nsg_assoc" {
  for_each                  = var.enable_nsg_association ? var.subnets : {}
  subnet_id                 = azurerm_subnet.subnets[each.key].id
  network_security_group_id = var.nsg_id
}

output "vnet_id" {
  value       = azurerm_virtual_network.vnet.id
  description = "Virtual Network ID"
}

output "subnet_ids" {
  value       = { for k, v in azurerm_subnet.subnets : k => v.id }
  description = "Map of created Subnet IDs keyed by their defined name suffix"
}
