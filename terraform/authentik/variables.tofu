variable "OP_SERVICE_ACCOUNT_TOKEN" {
  type        = string
  description = "1Password Service Account token"
  sensitive   = true
}

variable "CLUSTER_DOMAIN" {
  type        = string
  description = "Domain for Authentik"
  default     = "jory.dev"
}
