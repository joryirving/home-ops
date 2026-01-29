variable "OP_CONNECT_HOST" {
  type        = string
  description = "OnePassword Connect URL"
}

variable "OP_CONNECT_TOKEN" {
  type        = string
  description = "OnePassword Connect token"
  sensitive   = true
  default     = null
}

variable "CLUSTER_DOMAIN" {
  type        = string
  description = "Domain for Authentik"
  default     = "jory.dev"
}
