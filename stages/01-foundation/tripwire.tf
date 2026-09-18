# Activity-log tripwire: detection only. It reads AzureActivity and sends an email; it never
# changes a resource. Deleting it removes detection, not enforcement.
# NIST SP 800-53 Rev.5: AU-6 (audit review and reporting), CM-3 / CM-5 (change control and access
# restrictions for change), SI-4 (monitoring). CSF 2.0: DE.CM-01, DE.AE-02.

resource "azurerm_monitor_action_group" "grc_ops" {
  name                = "ag-grc-ops-${var.environment}"
  resource_group_name = azurerm_resource_group.sandbox.name
  short_name          = "grcops"

  email_receiver {
    name          = "owner"
    email_address = var.owner_email
  }

  tags = {
    env     = var.environment
    purpose = "cge-az-labs"
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "activity_tripwire" {
  name                = "alert-grc-activity-tripwire-${var.environment}"
  resource_group_name = azurerm_resource_group.sandbox.name
  location            = var.location
  display_name        = "GRC tripwire: out-of-band administrative change"
  description         = "A successful write or delete by anyone other than the remediation identity. Match it to a merged pull request."

  scopes               = [azurerm_log_analytics_workspace.grc.id]
  severity             = 2
  evaluation_frequency = "PT1H"
  window_duration      = "PT1H"

  criteria {
    # replace() pins the query to LF so a CRLF checkout cannot plan a rewrite of an unchanged rule.
    query = replace(templatefile("${path.module}/tripwire.kql", {
      remediation_principal_id = azurerm_user_assigned_identity.remediation.principal_id
    }), "\r\n", "\n")
    time_aggregation_method = "Count"
    operator                = "GreaterThan"
    threshold               = 0
  }

  action {
    action_groups = [azurerm_monitor_action_group.grc_ops.id]
  }

  tags = {
    env     = var.environment
    purpose = "cge-az-labs"
  }
}
