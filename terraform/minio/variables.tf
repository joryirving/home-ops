variable "onepassword_sa_token" {
  type        = string
  description = "Oneopass Service Account Token"
  sensitive   = true
}

variable "minio_url" {
  type        = string
  description = "Minio Server URL"
  default     = "s3.jory.dev"
}

variable "bw_access_token" {
  type        = string
  description = "Bitwarden Secret Manager Access token"
  sensitive   = true
}
