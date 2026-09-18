# Gate rule: storage must enforce encrypted transport.
# NIST SP 800-53 Rev.5: SC-8 (transmission confidentiality/integrity), SC-13 (cryptographic protection).
# CSF 2.0: PR.DS-02 (data in transit is protected).
package main

import rego.v1

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "azurerm_storage_account"
	rc.change.actions[_] != "delete"
	rc.change.after.min_tls_version != "TLS1_2"
	msg := sprintf("%s: min_tls_version must be TLS1_2 (found %v) [SC-8]", [rc.address, rc.change.after.min_tls_version])
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "azurerm_storage_account"
	rc.change.actions[_] != "delete"
	rc.change.after.https_traffic_only_enabled == false
	msg := sprintf("%s: HTTPS-only transfer must stay enabled [SC-8]", [rc.address])
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "azurerm_linux_function_app"
	rc.change.actions[_] != "delete"
	rc.change.after.https_only != true
	msg := sprintf("%s: function apps must be https_only [SC-8]", [rc.address])
}
