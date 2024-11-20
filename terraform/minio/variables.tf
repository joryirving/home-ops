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
