# Gate rule: no broad role grants sneak into governance code — not even yours,
# not even at 2 AM with a deadline.
package main

import rego.v1

broad_roles := {"Owner", "Contributor"}

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "azurerm_role_assignment"
	rc.change.actions[_] != "delete"
	rc.change.after.role_definition_name in broad_roles
	msg := sprintf("%s: %s at any scope is not a whitelist — use a granular role", [rc.address, rc.change.after.role_definition_name])
}
