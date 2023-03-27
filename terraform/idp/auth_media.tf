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

resource "authentik_provider_proxy" "proxy" {
  for_each = local.applications
  name     = each.value
  #internal_host      = "http://sonarr.media"
  external_host      = "http://${each.value}.lildrunkensmurf.com"
  authorization_flow = data.authentik_flow.default-authorization-flow.id
}

resource "authentik_application" "application" {
  for_each           = local.applications
  name               = authentik_provider_proxy.proxy[each.value].name
  slug               = authentik_provider_proxy.proxy[each.value].name
  protocol_provider  = authentik_provider_proxy.proxy[each.value].id
  group              = authentik_group.media.name
  open_in_new_tab    = true
  meta_icon          = "https://${each.value}.lildrunkensmurf.com/Content/Images/logo.svg"
  meta_launch_url    = "https://${each.value}.lildrunkensmurf.com"
  policy_engine_mode = "all"
}

# resource "authentik_provider_proxy" "radarr" {
#   name = "radarr"
#   #internal_host      = "http://radarr.media"
#   external_host      = "http://radarr.lildrunkensmurf.com"
#   authorization_flow = data.authentik_flow.default-authorization-flow.id
# }

# resource "authentik_application" "radarr" {
#   name               = authentik_provider_proxy.radarr.name
#   slug               = authentik_provider_proxy.radarr.name
#   protocol_provider  = authentik_provider_proxy.radarr.id
#   group              = authentik_group.media.name
#   open_in_new_tab    = true
#   meta_icon          = "https://radarr.lildrunkensmurf.com/Content/Images/logo.svg"
#   meta_launch_url    = "https://radarr.lildrunkensmurf.com"
#   policy_engine_mode = "all"
# }

# resource "authentik_outpost" "media_outpost" {
#   name = "media-outpost"
#   type = "proxy"
#   protocol_providers = [
#     authentik_provider_oauth2.sonarr.id,
#     authentik_provider_oauth2.radarr.id
#   ]
# }
