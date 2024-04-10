# locals {
#   media_applications = toset([
#     "overseerr",
#     "tautulli",
#   ])

#   download_applications = toset([
#     "bazarr",
#     "prowlarr",
#     "qbittorrent",
#     "radarr",
#     "readarr",
#     "sabnzbd",
#     "sonarr",
#   ])

#   infra_applications = toset([
#     "longhorn",
#     "nas",
#     "tdarr"
#   ])

#   proxy_list = concat(
#     values(authentik_provider_proxy.download_proxy)[*].id,
#     values(authentik_provider_proxy.media_proxy)[*].id,
#     values(authentik_provider_proxy.infra_proxy)[*].id,
#     [authentik_provider_proxy.hass_proxy.id]
#   )
# }

### Proxy Providers ###
## Downloads ##
# resource "authentik_provider_proxy" "download_proxy" {
#   for_each              = local.download_applications
#   name                  = "${each.value}"
#   external_host         = "http://${each.value}.${var.cluster_domain}"
#   mode                  = "forward_single"
#   authorization_flow    = resource.authentik_flow.provider-authorization-implicit-consent.uuid
#   access_token_validity = "hours=4"
# }

# resource "authentik_application" "download_application" {
#   for_each           = local.download_applications
#   name               = title(each.value)
#   slug               = authentik_provider_proxy.download_proxy[each.value].name
#   protocol_provider  = authentik_provider_proxy.download_proxy[each.value].id
#   group              = authentik_group.downloads.name
#   open_in_new_tab    = true
#   meta_icon          = "https://raw.githubusercontent.com/joryirving/home-ops/main/.docs/icons/${each.value}.png"
#   policy_engine_mode = "all"
# }

## Infra ##
# resource "authentik_provider_proxy" "infra_proxy" {
#   for_each              = local.infra_applications
#   name                  = "${each.value}"
#   external_host         = "http://${each.value}.${var.cluster_domain}"
#   mode                  = "forward_single"
#   authorization_flow    = resource.authentik_flow.provider-authorization-implicit-consent.uuid
#   access_token_validity = "hours=4"
# }

# resource "authentik_application" "infra_application" {
#   for_each           = local.infra_applications
#   name               = title(each.value)
#   slug               = authentik_provider_proxy.infra_proxy[each.value].name
#   protocol_provider  = authentik_provider_proxy.infra_proxy[each.value].id
#   group              = authentik_group.infrastructure.name
#   open_in_new_tab    = true
#   meta_icon          = "https://raw.githubusercontent.com/joryirving/home-ops/main/.docs/icons/${each.value}.png"
#   policy_engine_mode = "all"
# }

## Media ##
# resource "authentik_provider_proxy" "media_proxy" {
#   for_each                      = local.media_applications
#   name                          = "${each.value}"
#   basic_auth_enabled            = true
#   basic_auth_username_attribute = var.[each.value]_username #I don't know if this works
#   basic_auth_password_attribute = var.[each.value]_password
#   external_host                 = "http://${each.value}.${var.cluster_domain}"
#   mode                          = "forward_single"
#   authorization_flow            = resource.authentik_flow.provider-authorization-implicit-consent.uuid
#   access_token_validity         = "hours=4"
# }

# resource "authentik_application" "media_application" {
#   for_each           = local.media_applications
#   name               = title(each.value)
#   slug               = authentik_provider_proxy.media_proxy[each.value].name
#   protocol_provider  = authentik_provider_proxy.media_proxy[each.value].id
#   group              = authentik_group.media.name
#   open_in_new_tab    = true
#   meta_icon          = "https://raw.githubusercontent.com/joryirving/home-ops/main/.docs/icons/${each.value}.png"
#   policy_engine_mode = "all"
# }

## HASS ##
# resource "authentik_provider_proxy" "hass_proxy" {
#   name                  = "home-assistant"
#   external_host         = "http://hass.${var.cluster_domain}"
#   mode                  = "forward_single"
#   authorization_flow    = resource.authentik_flow.provider-authorization-implicit-consent.uuid
#   access_token_validity = "hours=4"
# }

# resource "authentik_application" "hass_application" {
#   name               = "Home-Assistant"
#   slug               = authentik_provider_proxy.hass_proxy.name
#   protocol_provider  = authentik_provider_proxy.hass_proxy.id
#   group              = authentik_group.home.name
#   open_in_new_tab    = true
#   meta_icon          = "https://raw.githubusercontent.com/walkxcode/dashboard-icons/main/png/home-assistant.png"
#   policy_engine_mode = "all"
# }

### Oauth2 Providers ###
## Grafana ##
resource "authentik_provider_oauth2" "grafana_oauth2" {
  name                  = "grafana"
  client_id             = var.grafana_id
  client_secret         = var.grafana_secret
  authorization_flow    = resource.authentik_flow.provider-authorization-implicit-consent.uuid
  property_mappings     = data.authentik_scope_mapping.oauth2.ids
  access_token_validity = "hours=4"
  redirect_uris         = ["https://grafana.${var.cluster_domain}/login/generic_oauth"]
}

resource "authentik_application" "grafana_application" {
  name               = "Grafana"
  slug               = authentik_provider_oauth2.grafana_oauth2.name
  protocol_provider  = authentik_provider_oauth2.grafana_oauth2.id
  group              = authentik_group.monitoring.name
  open_in_new_tab    = true
  meta_icon          = "https://raw.githubusercontent.com/walkxcode/dashboard-icons/main/png/grafana.png"
  meta_launch_url    = "https://grafana.${var.cluster_domain}/login/generic_oauth"
  policy_engine_mode = "all"
}

## LubeLog ##
resource "authentik_provider_oauth2" "lubelog_oauth2" {
  name                  = "lubelog"
  client_id             = var.lubelog_id
  client_secret         = var.lubelog_secret
  authorization_flow    = resource.authentik_flow.provider-authorization-implicit-consent.uuid
  property_mappings     = data.authentik_scope_mapping.oauth2.ids
  access_token_validity = "hours=4"
  redirect_uris         = ["https://lubelog.${var.cluster_domain}/Login/RemoteAuth"]
}

resource "authentik_application" "lubelog_application" {
  name               = "lubelog"
  slug               = authentik_provider_oauth2.lubelog_oauth2.name
  protocol_provider  = authentik_provider_oauth2.lubelog_oauth2.id
  group              = authentik_group.monitoring.name
  open_in_new_tab    = true
  meta_icon          = "https://demo.lubelogger.com/defaults/lubelogger_icon_72.png"
  meta_launch_url    = "https://lubelog.${var.cluster_domain}"
  policy_engine_mode = "all"
}

## Paperless ##
resource "authentik_provider_oauth2" "paperless_oauth2" {
  name                  = "paperless"
  client_id             = var.paperless_id
  client_secret         = var.paperless_secret
  authorization_flow    = resource.authentik_flow.provider-authorization-implicit-consent.uuid
  property_mappings     = data.authentik_scope_mapping.oauth2.ids
  access_token_validity = "hours=4"
  redirect_uris         = ["https://paperless.${var.cluster_domain}/accounts/oidc/authentik/login/callback/"]
}

resource "authentik_application" "paperless_application" {
  name               = "Paperless"
  slug               = authentik_provider_oauth2.paperless_oauth2.name
  protocol_provider  = authentik_provider_oauth2.paperless_oauth2.id
  group              = authentik_group.home.name
  open_in_new_tab    = true
  meta_icon          = "https://raw.githubusercontent.com/walkxcode/dashboard-icons/main/png/paperless.png"
  meta_launch_url    = "https://paperless.${var.cluster_domain}/"
  policy_engine_mode = "all"
}

## Portainer ##
resource "authentik_provider_oauth2" "portainer_oauth2" {
  name                  = "portainer"
  client_id             = var.portainer_id
  client_secret         = var.portainer_secret
  authorization_flow    = resource.authentik_flow.provider-authorization-implicit-consent.uuid
  property_mappings     = data.authentik_scope_mapping.oauth2.ids
  access_token_validity = "hours=4"
  redirect_uris         = ["https://portainer.${var.pi_cluster_domain}/"]
}

resource "authentik_application" "portainer_application" {
  name               = "Portainer"
  slug               = authentik_provider_oauth2.portainer_oauth2.name
  protocol_provider  = authentik_provider_oauth2.portainer_oauth2.id
  group              = authentik_group.infrastructure.name
  open_in_new_tab    = true
  meta_icon          = "https://raw.githubusercontent.com/walkxcode/dashboard-icons/main/png/portainer.png"
  meta_launch_url    = "https://portainer.${var.pi_cluster_domain}/"
  policy_engine_mode = "all"
}

## Weave-Gitops ##
resource "authentik_provider_oauth2" "gitops_oauth2" {
  name                  = "gitops"
  client_id             = var.gitops_id
  client_secret         = var.gitops_secret
  authorization_flow    = resource.authentik_flow.provider-authorization-implicit-consent.uuid
  property_mappings     = data.authentik_scope_mapping.oauth2.ids
  access_token_validity = "hours=4"
  redirect_uris         = ["https://gitops.${var.cluster_domain}/oauth2/callback"]
}

resource "authentik_application" "gitops_application" {
  name               = "Gitops"
  slug               = authentik_provider_oauth2.gitops_oauth2.name
  protocol_provider  = authentik_provider_oauth2.gitops_oauth2.id
  group              = authentik_group.infrastructure.name
  open_in_new_tab    = true
  meta_icon          = "https://raw.githubusercontent.com/joryirving/home-ops/main/.docs/icons/weave.png"
  meta_launch_url    = "https://gitops.${var.cluster_domain}/"
  policy_engine_mode = "all"
}

### Outpost ###
# resource "authentik_outpost" "proxyoutpost" {
#   name               = "proxy-outpost"
#   type               = "proxy"
#   service_connection = authentik_service_connection_kubernetes.local.id
#   protocol_providers = local.proxy_list
#   config = jsonencode({
#     authentik_host          = "https://sso.${var.cluster_domain}",
#     authentik_host_insecure = false,
#     authentik_host_browser  = "",
#     log_level               = "debug",
#     object_naming_template  = "ak-outpost-%(name)s",
#     docker_network          = null,
#     docker_map_ports        = true,
#     docker_labels           = null,
#     container_image         = null,
#     kubernetes_replicas     = 1,
#     kubernetes_namespace    = "security",
#     kubernetes_ingress_annotations = {
#       "cert-manager.io/cluster-issuer" = "letsencrypt-production"
#     },
#     kubernetes_ingress_secret_name = "proxy-outpost-tls",
#     kubernetes_service_type        = "ClusterIP",
#     kubernetes_disabled_components = [],
#     kubernetes_image_pull_secrets  = []
#   })
# }
