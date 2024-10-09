variable "name" {
  type        = string
  description = "Secret name"
}

variable "username" {
  type        = string
  description = "Secret username"
}

variable "password" {
  type        = string
  description = "Secret password"
}

variable "bw_proj_id" {
  type        = string
  description = "Bitwarden Secret Manager Project ID"
  sensitive   = true
}
