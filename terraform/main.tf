# ---------------------------------------------------------------------------
# Key Vault — fetch DB password at plan time (same vault as demo project)
# ---------------------------------------------------------------------------

data "azurerm_key_vault" "kv" {
  name                = "kv-secrets-1029"
  resource_group_name = "rg-terraform-state"
}

data "azurerm_key_vault_secret" "db_password" {
  name         = "taskflow-db-pass"
  key_vault_id = data.azurerm_key_vault.kv.id
}

# ---------------------------------------------------------------------------
# Resource Group
# ---------------------------------------------------------------------------

module "resource_group" {
  source      = "../../../modules/rg"
  environment = var.environment
  location    = var.location
}

# ---------------------------------------------------------------------------
# Network Security Groups
# ---------------------------------------------------------------------------

module "nsg_app" {
  source              = "../../../modules/nsg"
  environment         = "${var.environment}-app"
  location            = module.resource_group.location
  resource_group_name = module.resource_group.name
  security_rules      = var.nsg_rules_app
}

module "nsg_db" {
  source              = "../../../modules/nsg"
  environment         = "${var.environment}-db"
  location            = module.resource_group.location
  resource_group_name = module.resource_group.name
  security_rules      = var.nsg_rules_db
}

# ---------------------------------------------------------------------------
# Virtual Network & Subnets
# ---------------------------------------------------------------------------

module "vnet" {
  source                 = "../../../modules/vnet"
  environment            = var.environment
  location               = module.resource_group.location
  resource_group_name    = module.resource_group.name
  address_space          = var.vnet_address_space
  subnets                = var.subnets
  enable_nsg_association = false
}

resource "azurerm_subnet_network_security_group_association" "app_nsg_assoc" {
  subnet_id                 = module.vnet.subnet_ids["app"]
  network_security_group_id = module.nsg_app.id
}

resource "azurerm_subnet_network_security_group_association" "db_nsg_assoc" {
  subnet_id                 = module.vnet.subnet_ids["db"]
  network_security_group_id = module.nsg_db.id
}

# ---------------------------------------------------------------------------
# App VM  (NO custom_data — Ansible handles all configuration)
# ---------------------------------------------------------------------------

resource "azurerm_public_ip" "app_pip" {
  name                = "pip-app-${var.environment}"
  location            = module.resource_group.location
  resource_group_name = module.resource_group.name
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "app_nic" {
  name                = "nic-app-${var.environment}"
  location            = module.resource_group.location
  resource_group_name = module.resource_group.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = module.vnet.subnet_ids["app"]
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.app_pip.id
  }
}

resource "azurerm_linux_virtual_machine" "app_vm" {
  name                            = "vm-app-${var.environment}"
  resource_group_name             = module.resource_group.name
  location                        = module.resource_group.location
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.ssh_public_key_path)
  }

  network_interface_ids = [azurerm_network_interface.app_nic.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  # No custom_data — Ansible runs after provisioning via GitHub Actions
}

# ---------------------------------------------------------------------------
# DB VM  (NO custom_data — Ansible handles all configuration)
# ---------------------------------------------------------------------------

resource "azurerm_network_interface" "db_nic" {
  name                = "nic-db-${var.environment}"
  location            = module.resource_group.location
  resource_group_name = module.resource_group.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = module.vnet.subnet_ids["db"]
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "db_vm" {
  name                            = "vm-db-${var.environment}"
  resource_group_name             = module.resource_group.name
  location                        = module.resource_group.location
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.ssh_public_key_path)
  }

  network_interface_ids = [azurerm_network_interface.db_nic.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  # No custom_data — Ansible runs after provisioning via GitHub Actions
}
