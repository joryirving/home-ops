variable "OP_CONNECT_HOST" {
  type        = string
  description = "Oneopass Connect URL"
  default     = "http://voyager.internal:7070"
}

variable "OP_CONNECT_TOKEN" {
  type        = string
  description = "The path to the service account JSON for OnePassword."
  sensitive   = true
  default     = null
}

variable "MINIO_URL" {
  type        = string
  description = "Minio Server URL"
  default     = "s3.jory.dev"
}
