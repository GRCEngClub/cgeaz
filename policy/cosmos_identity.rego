# Gate rule: the evidence database is reachable by identity only.
# NIST SP 800-53 Rev.5: IA-2 (identification and authentication), IA-5 (authenticator management: no keys to leak),
# AC-3 (access enforcement through RBAC).
# CSF 2.0: PR.AA-01, PR.AA-05.
package main

import rego.v1

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "azurerm_cosmosdb_account"
	rc.change.actions[_] != "delete"
	rc.change.after.local_authentication_enabled != false
	msg := sprintf("%s: Cosmos DB local (key) authentication must be disabled [IA-5]", [rc.address])
}
