variable "location" {
  description = "Azure region for foundation resources."
  type        = string
  default     = "eastus"
}

variable "owner_email" {
  description = "Owner tag applied to governed resource groups; the POA&M generator resolves finding owners from it."
  type        = string
}

variable "environment" {
  description = "Environment name used in tags and resource names."
  type        = string
  default     = "dev"
}

variable "tag_policy_effect" {
  description = "Effect for the require-env-tag policy (Audit while onboarding, Deny once clean)."
  type        = string
  default     = "Audit"
  validation {
    condition     = contains(["Audit", "Deny", "Disabled"], var.tag_policy_effect)
    error_message = "tag_policy_effect must be Audit, Deny, or Disabled."
  }
}

variable "public_blob_policy_effect" {
  description = "Effect for the deny-public-blob-access policy. This one has earned Deny."
  type        = string
  default     = "Deny"
  validation {
    condition     = contains(["Audit", "Deny", "Disabled"], var.public_blob_policy_effect)
    error_message = "public_blob_policy_effect must be Audit, Deny, or Disabled."
  }
}
