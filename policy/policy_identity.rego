# Gate rule: a policy assignment carrying remediation effects without an identity
# applies cleanly and then silently never remediates. Make that mistake unmergeable.
# NIST SP 800-53 Rev.5: SI-2 (flaw remediation actually happens), CM-3 (controlled change).
# CSF 2.0: ID.IM-01, PR.PS-01.
package main

import rego.v1

assignment_types := {
	"azurerm_management_group_policy_assignment",
	"azurerm_subscription_policy_assignment",
	"azurerm_resource_group_policy_assignment",
}

# Terraform plan JSON renders an absent block as `identity: []`, and `not []` is
# false in Rego, so the check has to count entries rather than test truthiness.
has_identity(rc) if count(rc.change.after.identity) > 0

deny contains msg if {
	some rc in input.resource_changes
	rc.type in assignment_types
	rc.change.actions[_] != "delete"
	not has_identity(rc)
	msg := sprintf("%s: policy assignments must carry an identity block (remediation effects silently no-op without one)", [rc.address])
}
