terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
  }

  # Remote state in Azure Storage — same backend as demo project
  backend "azurerm" {
    resource_group_name  = "rg-bilal-gillani"
    storage_account_name = "stgtfstate1029"
    container_name       = "tfstate"
    key                  = "cicd-pipeline.terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
  tenant_id       = var.tenant_id
  subscription_id = var.subscription_id
}
