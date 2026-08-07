terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
  }

  # Remote state in Azure Storage
  backend "azurerm" {
    resource_group_name  = "rg-bilal-gillani"
    storage_account_name = "stgtfstate1029"
    container_name       = "tfstate"
    key                  = "cicd-pipeline.terraform.tfstate"
    use_oidc             = true   # authenticate to backend via OIDC, not az CLI
  }
}

provider "azurerm" {
  features {}
  use_oidc        = true   # authenticate via OIDC token, not az CLI session
  tenant_id       = var.tenant_id
  subscription_id = var.subscription_id
}
