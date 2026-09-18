variable "environment" {
  type    = string
  default = "dev"
}

variable "functions_location" {
  description = "Region for the reporting Function tier. Same free-account quota constraint as stage 03 — probe with labs/00-setup/probe-quota.sh."
  type        = string
  default     = "centralus"
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
