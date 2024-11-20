variable "cluster_domain" {
  type        = string
  description = "Domain for Authentik"
  default     = "jory.dev"
}

variable "onepassword_sa_token" {
  type        = string
  description = "Oneopass Service Account Token"
  sensitive   = true
}

variable "bw_access_token" {
  type        = string
  description = "Bitwarden Secret Manager Access token"
  sensitive   = true
}
