variable "baseline_plans" {
  description = "Defender plans the course baseline requires at Standard, mapped to their subplan (Azure stamps a default subplan on enablement; omitting it in config forces replacement on every run — we validated that churn so you don't have to). Empty string = no subplan. Each plan has a 30-day free trial; teardown flips them back to Free."
  type        = map(string)
  default = {
    StorageAccounts = "DefenderForStorageV2"
    KeyVaults       = "PerKeyVault"
  }
}

variable "subscription_id" {
  description = "Subscription every resource in this stage is created in. Explicit, never inferred from whichever `az login` happens to be active."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be a subscription GUID."
  }
}
