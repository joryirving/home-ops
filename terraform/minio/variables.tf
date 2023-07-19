variable "BW_PASSWORD" {
  type        = string
  description = "Bitwarden Master Key"
  sensitive   = true
}

variable "BW_CLIENTID" {
  type        = string
  description = "Bitwarden Client ID"
  sensitive   = true
}

variable "BW_CLIENTSECRET" {
  type        = string
  description = "Bitwarden Client Secret"
  sensitive   = true
}

variable "SECRET_DOMAIN" {
  type        = string
  description = "Domain"
  sensitive   = true
}
