data "authentik_certificate_key_pair" "generated" {
  name = "authentik Self-signed Certificate"
}

resource "authentik_tenant" "home" {
  domain           = data.sops_file.authentik_secrets.data["cluster_domain"]
  default          = false
  branding_title   = "Home"
  branding_logo    = "/static/dist/assets/icons/icon_left_brand.svg"
  branding_favicon = "/static/dist/assets/icons/icon.png"

  flow_authentication = authentik_flow.authentication.uuid
  flow_invalidation   = authentik_flow.invalidation.uuid
  # flow_user_settings  = data.authentik_flow.default-user-settings.id
  flow_user_settings = authentik_flow.user-settings.uuid
  event_retention    = "days=365"
}

resource "authentik_service_connection_kubernetes" "local" {
  name  = "local"
  local = true
}
