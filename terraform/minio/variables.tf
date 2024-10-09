variable "bw_access_token" {
  type        = string
  description = "Bitwarden Secret Manager Access token"
  sensitive   = true
}

variable "bw_org_id" {
  type        = string
  description = "Bitwarden Secret Manager Organization ID"
  sensitive   = true
}

variable "bw_proj_id" {
  type        = string
  description = "Bitwarden Secret Manager Project ID"
  sensitive   = true
}

variable "bw_minio_secret_id" {
  type        = string
  description = "Bitwarden Secret Manager Secret ID for Minio Credentials"
  sensitive   = true
}

variable "minio_url" {
  type        = string
  description = "Minio Server URL"
  sensitive   = true
}
