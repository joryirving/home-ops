variable "onepassword_connect" {
  type        = string
  description = "Oneopass Connect URL"
  default     = "http://voyager.internal:7070"
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
