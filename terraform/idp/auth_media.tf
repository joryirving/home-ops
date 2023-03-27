resource "authentik_group" "media_admin" {
  name         = "media_admin"
  is_superuser = false
}

resource "authentik_group" "media" {
  name         = "media"
  is_superuser = false
}

resource "authentik_source_oauth" "discord" {
  name                = "discord"
  slug                = "discord"
  authentication_flow = data.authentik_flow.default-authorization-flow.id
  enrollment_flow     = data.authentik_flow.default-authorization-flow.id

  provider_type   = "discord"
  consumer_key    = var.client_id
  consumer_secret = var.client_secret
}

resource "authentik_service_connection_kubernetes" "local" {
  name  = "local"
  local = true
}

resource "authentik_outpost" "media_outpost" {
  name               = "media-outpost"
  type               = "proxy"
  service_connection = authentik_service_connection_kubernetes.local.id
  protocol_providers = [
    for s in local.applications : authentik_provider_proxy.proxy[s].id
  ]
}
