terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  backend "azurerm" {
    key              = "06-enforcement.tfstate"
    use_azuread_auth = true
  }
}

provider "azurerm" {
  features {}
}

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

locals {
  mg_id          = data.terraform_remote_state.foundation.outputs.management_group_id
  remediation_id = data.terraform_remote_state.foundation.outputs.remediation_identity_id
  remediation_pid = data.terraform_remote_state.foundation.outputs.remediation_identity_principal_id

  # The escalation ladder, wired to one variable. Each step up is a reviewed PR:
  #   audit   -> observe only; count what would change
  #   dry-run -> modify effect deployed, but enforcement_mode DoNotEnforce;
  #              you create the remediation task manually = the human approval
  #   enforce -> modify effect, enforced automatically
  effect           = var.remediation_mode == "audit" ? "Audit" : "Modify"
  enforcement_mode = var.remediation_mode == "enforce" ? "Default" : "DoNotEnforce"
}

# blast radius: flips allowBlobPublicAccess to false on existing storage accounts
# under mg-grc-sandbox. Cannot delete anything, cannot read data, cannot touch
# any other property. rollback: set remediation_mode back to "audit" and merge.
resource "azurerm_policy_definition" "fix_public_blob" {
  name                = "cge-fix-public-blob"
  display_name        = "Remediate: disable public blob access on storage accounts"
  policy_type         = "Custom"
  mode                = "Indexed"
  management_group_id = local.mg_id

  policy_rule = jsonencode({
    if = {
      allOf = [
        { field = "type", equals = "Microsoft.Storage/storageAccounts" },
        { field = "Microsoft.Storage/storageAccounts/allowBlobPublicAccess", notEquals = "false" }
      ]
    }
    then = {
      effect = local.effect == "Audit" ? "Audit" : "Modify"
      details = local.effect == "Audit" ? null : {
        roleDefinitionIds = [
          # Storage Account Contributor — the narrowest built-in that can write this property
          "/providers/Microsoft.Authorization/roleDefinitions/17d1049b-9a84-46fb-8f53-869881c3d3ab"
        ]
        conflictEffect = "audit"
        operations = [
          { operation = "addOrReplace", field = "Microsoft.Storage/storageAccounts/allowBlobPublicAccess", value = false }
        ]
      }
    }
  })
}

resource "azurerm_management_group_policy_assignment" "fix_public_blob" {
  name                 = "cge-fix-public-blob"
  display_name         = "Remediate public blob access (${var.remediation_mode})"
  policy_definition_id = azurerm_policy_definition.fix_public_blob.id
  management_group_id  = local.mg_id
  location             = var.location
  enforce              = local.enforcement_mode == "Default"

  identity {
    type         = "UserAssigned"
    identity_ids = [local.remediation_id]
  }
}

# The remediation identity earns the storage role only when remediation can actually run.
resource "azurerm_role_assignment" "remediation_storage" {
  count                = var.remediation_mode == "audit" ? 0 : 1
  scope                = local.mg_id
  role_definition_name = "Storage Account Contributor"
  principal_id         = local.remediation_pid
}

output "remediation_mode" {
  value = var.remediation_mode
}
