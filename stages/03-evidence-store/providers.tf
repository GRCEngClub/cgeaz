terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  backend "azurerm" {
    key              = "03-evidence-store.tfstate"
    use_azuread_auth = true
  }
}

provider "azurerm" {
  features {}
  # Data-plane operations (containers, blobs) authenticate with Entra ID, not account keys —
  # required because the evidence storage account disables shared keys entirely.
  storage_use_azuread = true
}

# Stage contract: consume the foundation's outputs, never its internals.
data "terraform_remote_state" "foundation" {
  backend = "azurerm"
  config = {
    resource_group_name  = var.state_resource_group
    storage_account_name = var.state_storage_account
    container_name       = "tfstate"
    key                  = "01-foundation.tfstate"
    use_azuread_auth     = true
  }
}
