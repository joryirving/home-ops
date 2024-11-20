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
