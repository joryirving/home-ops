variable "OP_CONNECT_HOST" {
  type        = string
  description = "Oneopass Connect URL"
}

variable "OP_CONNECT_TOKEN" {
  type        = string
  description = "The path to the service account JSON for OnePassword."
  sensitive   = true
  default     = null
}

variable "CLUSTER_DOMAIN" {
  type        = string
  description = "Domain for Authentik"
  default     = "jory.dev"
}
