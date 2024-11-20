variable "onepassword_connect_token" {
  type        = string
  description = "1Pass Access token"
  sensitive   = true
}


variable "minio_url" {
  type        = string
  description = "Minio Server URL"
  default     = "s3.jory.dev"
}
