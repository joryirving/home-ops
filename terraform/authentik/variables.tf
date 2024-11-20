variable "onepassword_sa_token" {
  type        = string
  description = "Oneopass Service Account Token"
  sensitive   = true
  default     = null
}

variable "service_account_json" {
  type        = string
  description = "The path to the service account JSON for OnePassword."
  sensitive   = true
  default     = null
}

variable "cluster_domain" {
  type        = string
  description = "Domain for Authentik"
  default     = "jory.dev"
}
