variable "onepassword_sa_token" {
  type        = string
  description = "Oneopass Service Account Token"
  sensitive   = true
  default     = null
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
