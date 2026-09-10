variable "baseline_plans" {
  description = "Defender plans the course baseline requires at Standard, mapped to their subplan (Azure stamps a default subplan on enablement; omitting it in config forces replacement on every run — we validated that churn so you don't have to). Empty string = no subplan. Each plan has a 30-day free trial; teardown flips them back to Free."
  type        = map(string)
  default = {
    StorageAccounts = "DefenderForStorageV2"
    KeyVaults       = "PerKeyVault"
  }
}
