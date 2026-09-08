# Gate rule: a policy assignment carrying remediation effects without an identity
# applies cleanly and then silently never remediates. Make that mistake unmergeable.
package main

import rego.v1

assignment_types := {
	"azurerm_management_group_policy_assignment",
	"azurerm_subscription_policy_assignment",
	"azurerm_resource_group_policy_assignment",
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type in assignment_types
	rc.change.actions[_] != "delete"
	not rc.change.after.identity
	msg := sprintf("%s: policy assignments must carry an identity block (remediation effects silently no-op without one)", [rc.address])
}
