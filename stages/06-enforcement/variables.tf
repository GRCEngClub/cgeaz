variable "remediation_mode" {
  description = "Escalation ladder: audit -> dry-run -> enforce. Each step up should be a reviewed PR — automation acts, humans authorize."
  type        = string
  default     = "dry-run"
  validation {
    condition     = contains(["audit", "dry-run", "enforce"], var.remediation_mode)
    error_message = "remediation_mode must be audit, dry-run, or enforce."
  }
}

variable "location" {
  type    = string
  default = "eastus"
}

variable "state_resource_group" {
  type    = string
  default = "rg-grc-tfstate"
}

variable "state_storage_account" {
  type = string
}

variable "subscription_id" {
  description = "Subscription every resource in this stage is created in. Explicit, never inferred from whichever `az login` happens to be active."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be a subscription GUID."
  }
}
