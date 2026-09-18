# --- The collector Function App: timer-triggered Python, managed identity, zero keys. ---
# One app for collectors, a separate app (stage 04) for reporting: the Function App is
# the identity boundary, and no identity both writes evidence and generates reports.

# Internal plumbing storage for the Functions runtime (NOT the evidence store —
# that account has shared keys disabled; this one is the app's own scratch space).
resource "azurerm_storage_account" "func_internal" {
  name                            = "stgrcfunc${random_string.suffix.result}"
  resource_group_name             = local.evidence_rg
  location                        = var.functions_location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false

  # Scratch account, but the same hygiene as the evidence account: recoverable deletes and
  # short-lived SAS. Shared keys stay on only because the Functions runtime requires them.
  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }
  sas_policy {
    expiration_period = "01.00:00:00"
  }
  tags = local.common_tags
}

resource "azurerm_service_plan" "collectors" {
  name                = "asp-grc-collectors-${var.environment}"
  resource_group_name = local.evidence_rg
  location            = var.functions_location
  os_type             = "Linux"
  sku_name            = "Y1" # Consumption: pay per execution. Pennies.
  tags                = local.common_tags
}

# Workspace-based Application Insights: without it a failed timer run leaves no exception trail.
resource "azurerm_application_insights" "collectors" {
  name                = "appi-grc-collectors-${random_string.suffix.result}"
  resource_group_name = local.evidence_rg
  location            = var.functions_location
  workspace_id        = data.terraform_remote_state.foundation.outputs.log_analytics_workspace_id
  application_type    = "web"
  tags                = local.common_tags
}

resource "azurerm_linux_function_app" "collectors" {
  name                       = "func-grc-collectors-${random_string.suffix.result}"
  resource_group_name        = local.evidence_rg
  location                   = var.functions_location
  https_only                 = true
  service_plan_id            = azurerm_service_plan.collectors.id
  storage_account_name       = azurerm_storage_account.func_internal.name
  storage_account_access_key = azurerm_storage_account.func_internal.primary_access_key

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_insights_connection_string = azurerm_application_insights.collectors.connection_string
    application_stack {
      python_version = "3.11"
    }
  }

  app_settings = {
    "COSMOS_ENDPOINT"                = azurerm_cosmosdb_account.evidence.endpoint
    "COSMOS_DATABASE"                = azurerm_cosmosdb_sql_database.grc.name
    "SUBSCRIPTION_ID"                = local.subscription
    "DEFAULT_OWNER"                  = var.owner_email
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = "true"
    "ENABLE_ORYX_BUILD"              = "true"
  }

  # `az functionapp deployment source config-zip --build-remote` removes and re-adds this
  # setting on every deploy; Terraform must not fight the deploy tooling over it.
  lifecycle {
    ignore_changes = [app_settings["ENABLE_ORYX_BUILD"]]
  }

  tags = local.common_tags
}

# --- The collector identity's whitelist: read posture, write evidence. Nothing else. ---

# Security Reader at the subscription: read Defender assessments, change nothing.
resource "azurerm_role_assignment" "collector_security_reader" {
  scope                = "/subscriptions/${local.subscription}"
  role_definition_name = "Security Reader"
  principal_id         = azurerm_linux_function_app.collectors.identity[0].principal_id
}

# Cosmos data-plane write. "Cosmos DB Built-in Data Contributor" (00000000-0000-0000-0000-000000000002)
# is a Cosmos-native data-plane role, not an ARM role — control plane vs data plane, again.
resource "azurerm_cosmosdb_sql_role_assignment" "collector_cosmos_write" {
  resource_group_name = local.evidence_rg
  account_name        = azurerm_cosmosdb_account.evidence.name
  role_definition_id  = "${azurerm_cosmosdb_account.evidence.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = azurerm_linux_function_app.collectors.identity[0].principal_id
  scope               = azurerm_cosmosdb_account.evidence.id
}
