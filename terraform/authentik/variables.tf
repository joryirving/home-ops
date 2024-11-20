variable "cluster_domain" {
  type        = string
  description = "Domain for Authentik"
  default     = "jory.dev"
}

variable "onepassword_connect_token" {
  type        = string
  description = "1Pass Access token"
  sensitive   = true
}
