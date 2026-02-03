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

variable "GARAGE_URL" {
  type        = string
  description = "Garage Server URL"
  default     = "garage-api.jory.dev"
}
