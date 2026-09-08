terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # Backend values come from labs/03-foundation/backend.hcl (written by bootstrap.sh).
  # Init with: terraform init -backend-config=../../labs/03-foundation/backend.hcl
  backend "azurerm" {
    key              = "01-foundation.tfstate"
    use_azuread_auth = true
  }
}

provider "azurerm" {
  features {}
  # Set via ARM_SUBSCRIPTION_ID; azurerm 4.x requires explicit subscription targeting.
}
