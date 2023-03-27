locals {
  applications = toset([
    "sonarr",
    "radarr"
  ])
}

resource "authentik_provider_proxy" "proxy" {
  for_each           = local.applications
  name               = each.value
  internal_host      = "http://${each.value}.media"
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
