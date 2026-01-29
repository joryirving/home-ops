variable "OP_CONNECT_HOST" {
  type        = string
  description = "1Password Connect URL"
}

variable "OP_CONNECT_TOKEN" {
  type        = string
  description = "The path to the service account JSON for OnePassword."
  sensitive   = true
  default     = null
}
