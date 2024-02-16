variable "cluster_domain" {
  type        = string
  description = "Domain for Authentik"
  sensitive   = true
}

variable "pi_cluster_domain" {
  type        = string
  description = "Domain for Authentik"
  sensitive   = true
  default     = null
}

variable "gitops_id" {
  type        = string
  description = "Weave-Gitops Client ID"
  sensitive   = true
}

variable "gitops_secret" {
  type        = string
  description = "Weave-Gitops Client Secret"
  sensitive   = true
}

variable "grafana_id" {
  type        = string
  description = "Grafana Client ID"
  sensitive   = true
}

variable "grafana_secret" {
  type        = string
  description = "Grafana Client Secret"
  sensitive   = true
}

variable "lubelog_id" {
  type        = string
  description = "Lubelog Client ID"
  sensitive   = true
}

variable "lubelog_secret" {
  type        = string
  description = "Lubelog Client Secret"
  sensitive   = true
}

variable "paperless_id" {
  type        = string
  description = "Paperless Client ID"
  sensitive   = true
}

variable "paperless_secret" {
  type        = string
  description = "Paperless Client Secret"
  sensitive   = true
}

variable "portainer_id" {
  type        = string
  description = "Portainer Client ID"
  sensitive   = true
}

variable "portainer_secret" {
  type        = string
  description = "Portainer Client Secret"
  sensitive   = true
}

variable "discord_client_id" {
  type        = string
  description = "Discord Client ID"
  sensitive   = true
}

variable "discord_client_secret" {
  type        = string
  description = "Discord Client Secret"
  sensitive   = true
}

variable "authentik_token" {
  type        = string
  description = "Authentik Token"
  sensitive   = true
}
