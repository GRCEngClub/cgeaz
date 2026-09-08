# Gate rule: the pipeline's own storage must pass the pipeline's own standard.
# Any storage account in a plan must disable public blob access and shared keys.
package main

import rego.v1

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "azurerm_storage_account"
	rc.change.after.allow_nested_items_to_be_public == true
	msg := sprintf("%s: storage accounts must not allow public blob access", [rc.address])
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "azurerm_storage_account"
	rc.change.after.shared_access_key_enabled == true
	not startswith(rc.name, "func_internal")
	msg := sprintf("%s: shared key access must be disabled (identity or nothing) — func runtime storage is the documented exception", [rc.address])
}
