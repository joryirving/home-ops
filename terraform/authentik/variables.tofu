variable "OP_CONNECT_HOST" {
  type        = string
  description = "1Password Connect API URL"
}

variable "OP_CONNECT_TOKEN" {
  type        = string
  description = "1Password Connect API token"
  sensitive   = true
  default     = null
}

variable "CLUSTER_DOMAIN" {
  type        = string
  description = "Domain for Authentik"
  default     = "jory.dev"
}
