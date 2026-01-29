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
