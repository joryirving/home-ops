variable "onepassword_connect" {
  type        = string
  description = "Oneopass Connect URL"
  default     = "http://voyager.internal:7070"
}

variable "service_account_json" {
  type        = string
  description = "The path to the service account JSON for OnePassword."
  sensitive   = true
  default     = null
}

variable "minio_url" {
  type        = string
  description = "Minio Server URL"
  default     = "s3.jory.dev"
}
