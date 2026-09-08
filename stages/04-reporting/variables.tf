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
