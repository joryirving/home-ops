variable "OP_SERVICE_ACCOUNT_TOKEN" {
  type        = string
  description = "1Password Service Account token"
  sensitive   = true
}

variable "GARAGE_URL" {
  type        = string
  description = "Garage Server URL"
  default     = "garage-api.jory.dev"
}
