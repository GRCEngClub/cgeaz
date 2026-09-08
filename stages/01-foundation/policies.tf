# Three policies, one initiative, assigned once at mg-grc-sandbox.
# Every subscription that ever joins the sandbox group inherits all of it. (CSF: GV.PO, PR.DS, PR.PS)

# --- 1. Require the `env` tag on resource groups (inventory hygiene; POA&M owner resolution) ---

resource "azurerm_policy_definition" "require_env_tag" {
  name                = "cge-require-env-tag-rg"
  display_name        = "Resource groups must carry an env tag"
  policy_type         = "Custom"
  mode                = "All"
  management_group_id = azurerm_management_group.sandbox.id

  parameters = jsonencode({
    effect = {
      type = "String"
      allowedValues = ["Audit", "Deny", "Disabled"]
      defaultValue  = "Audit"
    }
  })

  policy_rule = jsonencode({
    if = {
      allOf = [
        { field = "type", equals = "Microsoft.Resources/subscriptions/resourceGroups" },
        { field = "tags['env']", exists = "false" }
      ]
    }
    then = { effect = "[parameters('effect')]" }
  })
}

# --- 2. Deny public blob access on storage accounts (clear-cut, framework-mandated: earned Deny) ---

resource "azurerm_policy_definition" "deny_public_blob" {
  name                = "cge-deny-public-blob"
  display_name        = "Storage accounts must not allow public blob access"
  policy_type         = "Custom"
  mode                = "Indexed"
  management_group_id = azurerm_management_group.sandbox.id

  parameters = jsonencode({
    effect = {
      type = "String"
      allowedValues = ["Audit", "Deny", "Disabled"]
      defaultValue  = "Deny"
    }
  })

  policy_rule = jsonencode({
    if = {
      allOf = [
        { field = "type", equals = "Microsoft.Storage/storageAccounts" },
        { field = "Microsoft.Storage/storageAccounts/allowBlobPublicAccess", equals = "true" }
      ]
    }
    then = { effect = "[parameters('effect')]" }
  })
}

# --- 3. deployIfNotExists: storage accounts missing diagnostic settings get them, routed to the GRC workspace ---
# Logging that enforces its own coverage. Remediation runs AS the identity in identity.tf.

resource "azurerm_policy_definition" "storage_diagnostics" {
  name                = "cge-dine-storage-diagnostics"
  display_name        = "Storage accounts must route diagnostics to the GRC workspace"
  policy_type         = "Custom"
  mode                = "Indexed"
  management_group_id = azurerm_management_group.sandbox.id

  parameters = jsonencode({
    workspaceId = {
      type     = "String"
      metadata = { displayName = "Log Analytics workspace resource ID" }
    }
  })

  policy_rule = jsonencode({
    if = {
      field  = "type"
      equals = "Microsoft.Storage/storageAccounts"
    }
    then = {
      effect = "DeployIfNotExists"
      details = {
        type = "Microsoft.Insights/diagnosticSettings"
        roleDefinitionIds = [
          # Monitoring Contributor
          "/providers/Microsoft.Authorization/roleDefinitions/749f88d5-cbae-40b8-bcfc-e573ddc772fa"
        ]
        existenceCondition = {
          allOf = [
            { field = "Microsoft.Insights/diagnosticSettings/workspaceId", equals = "[parameters('workspaceId')]" }
          ]
        }
        deployment = {
          properties = {
            mode = "incremental"
            parameters = {
              resourceName = { value = "[field('name')]" }
              workspaceId  = { value = "[parameters('workspaceId')]" }
              location     = { value = "[field('location')]" }
            }
            template = {
              "$schema"      = "https://schema.management.azure.com/schemas/2015-01-01/deploymentTemplate.json#"
              contentVersion = "1.0.0.0"
              parameters = {
                resourceName = { type = "string" }
                workspaceId  = { type = "string" }
                location     = { type = "string" }
              }
              resources = [
                {
                  type       = "Microsoft.Storage/storageAccounts/providers/diagnosticSettings"
                  apiVersion = "2021-05-01-preview"
                  name       = "[concat(parameters('resourceName'), '/Microsoft.Insights/ds-to-grc-workspace')]"
                  properties = {
                    workspaceId = "[parameters('workspaceId')]"
                    metrics = [
                      { category = "Transaction", enabled = true }
                    ]
                  }
                }
              ]
            }
          }
        }
      }
    }
  })
}

# --- The initiative: one assignment, whole-sandbox inheritance ---

resource "azurerm_management_group_policy_set_definition" "grc_baseline" {
  name                = "cge-grc-baseline"
  display_name        = "CGE-AZ GRC Baseline"
  policy_type         = "Custom"
  management_group_id = azurerm_management_group.sandbox.id

  parameters = jsonencode({
    tagEffect        = { type = "String", defaultValue = "Audit" }
    publicBlobEffect = { type = "String", defaultValue = "Deny" }
    workspaceId      = { type = "String" }
  })

  policy_definition_reference {
    policy_definition_id = azurerm_policy_definition.require_env_tag.id
    parameter_values = jsonencode({
      effect = { value = "[parameters('tagEffect')]" }
    })
  }

  policy_definition_reference {
    policy_definition_id = azurerm_policy_definition.deny_public_blob.id
    parameter_values = jsonencode({
      effect = { value = "[parameters('publicBlobEffect')]" }
    })
  }

  policy_definition_reference {
    policy_definition_id = azurerm_policy_definition.storage_diagnostics.id
    parameter_values = jsonencode({
      workspaceId = { value = "[parameters('workspaceId')]" }
    })
  }
}

resource "azurerm_management_group_policy_assignment" "grc_baseline" {
  name                 = "cge-grc-baseline"
  display_name         = "CGE-AZ GRC Baseline"
  policy_definition_id = azurerm_management_group_policy_set_definition.grc_baseline.id
  management_group_id  = azurerm_management_group.sandbox.id
  location             = var.location

  parameters = jsonencode({
    tagEffect        = { value = var.tag_policy_effect }
    publicBlobEffect = { value = var.public_blob_policy_effect }
    workspaceId      = { value = azurerm_log_analytics_workspace.grc.id }
  })

  # Remediation effects (deployIfNotExists) execute AS this identity.
  # Without this block, Terraform applies cleanly and remediation silently never runs.
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.remediation.id]
  }
}
