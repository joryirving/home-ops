variable "authentik_bootstrap_token" {
  sensitive = true
}

variable "authentik_from_address" {
  default = "authentik@tylercash.dev"
}

variable "client_id" {
  description = "Discord Client ID"
  sensitive   = true
}

variable "client_secret" {
  description = "Discord Client Secret"
  sensitive   = true
}
