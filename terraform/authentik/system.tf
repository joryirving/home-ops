data "authentik_certificate_key_pair" "generated" {
  name = "authentik Self-signed Certificate"
}

data "authentik_brand" "authentik-default" {
  domain = "authentik-default"
}

# Get the default flows
data "authentik_flow" "default-brand-authentication" {
  slug = "default-authentication-flow"
}

data "authentik_flow" "default-brand-invalidation" {
  slug = "default-invalidation-flow"
}

data "authentik_flow" "default-brand-user-settings" {
  slug = "default-user-settings-flow"
}

import {
  to = authentik_brand.default
  id = data.authentik_brand.authentik-default.id
}

# Create/manage the default brand
resource "authentik_brand" "default" {
  domain           = "authentik-default"
  default          = false
  branding_title   = "authentik"
  branding_logo    = "/static/dist/assets/icons/icon_left_brand.svg"
  branding_favicon = "/static/dist/assets/icons/icon.png"

  flow_authentication = data.authentik_flow.default-brand-authentication.id
  flow_invalidation   = data.authentik_flow.default-brand-invalidation.id
  flow_user_settings  = data.authentik_flow.default-brand-user-settings.id
}

resource "authentik_brand" "home" {
  domain           = var.CLUSTER_DOMAIN
  default          = true
  branding_title   = "Home"
  branding_logo    = "/static/dist/assets/icons/icon_left_brand.svg"
  branding_favicon = "/static/dist/assets/icons/icon.png"

  flow_authentication = authentik_flow.authentication.uuid
  flow_invalidation   = authentik_flow.invalidation.uuid
  flow_user_settings  = authentik_flow.user-settings.uuid
}

resource "authentik_service_connection_kubernetes" "local" {
  name  = "local"
  local = true
}
