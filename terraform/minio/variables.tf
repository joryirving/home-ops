variable "bw_password" {
  type        = string
  description = "Bitwarden Master Key"
  sensitive   = true
}

variable "bw_client_id" {
  type        = string
  description = "Bitwarden Client ID"
  sensitive   = true
}

variable "bw_client_secret" {
  type        = string
  description = "Bitwarden Client Secret"
  sensitive   = true
}

variable "bw_email" {
  type        = string
  description = "Bitwarden Email Login"
  sensitive   = true
}

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
  description = "Bitwarden ID for Minio Secret"
  sensitive   = true
}

variable "minio_url" {
  type        = string
  description = "Minio URL"
  sensitive   = true
}
