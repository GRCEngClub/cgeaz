# The remediation identity: one named, auditable identity through which every automated fix flows.
# Its roles are a whitelist of its job — never Contributor, never Owner.
# Filter the Activity Log by this caller and you have your complete automated-change history.

resource "azurerm_user_assigned_identity" "remediation" {
  name                = "id-grc-remediation-${var.environment}"
  location            = var.location
  resource_group_name = azurerm_resource_group.sandbox.name
  tags = {
    env     = var.environment
    purpose = "policy-remediation"
  }
}

# blast radius: can create/update diagnostic settings and other monitoring config
# under the sandbox management group. Cannot create, delete, or read data from resources.
# rollback: remove this role assignment; in-flight remediation tasks fail closed.
resource "azurerm_role_assignment" "remediation_monitoring" {
  scope                = azurerm_management_group.sandbox.id
  role_definition_name = "Monitoring Contributor"
  principal_id         = azurerm_user_assigned_identity.remediation.principal_id
}
