locals {
  media_applications = toset([
    "bazarr",
    "overseerr",
    "prowlarr",
    "qbittorrent",
    "radarr",
    "readarr",
    "sabnzbd",
    "sonarr",
    "tautulli",
  ])

  infra_applications = toset([
    "nas",
    "portainer",
    "tdarr"
  ])

  proxy_list = concat(
    values(authentik_provider_proxy.media_proxy)[*].id,
    values(authentik_provider_proxy.infra_proxy)[*].id
  )
}

resource "authentik_provider_proxy" "media_proxy" {
  for_each                      = local.media_applications
  name                          = "${each.value}-provider"
  basic_auth_enabled            = true
  basic_auth_username_attribute = data.sops_file.authentik_secrets.data["${each.value}_username"]
  basic_auth_password_attribute = data.sops_file.authentik_secrets.data["${each.value}_password"]
  external_host                 = "http://${each.value}.${data.sops_file.authentik_secrets.data["cluster_domain"]}"
  mode                          = "forward_single"
  authorization_flow            = resource.authentik_flow.provider-authorization-implicit-consent.uuid
  access_token_validity         = "hours=4"
}

resource "authentik_application" "media_application" {
  for_each           = local.media_applications
  name               = title(each.value)
  slug               = authentik_provider_proxy.media_proxy[each.value].name
  protocol_provider  = authentik_provider_proxy.media_proxy[each.value].id
  group              = authentik_group.media.name
  open_in_new_tab    = true
  meta_icon          = "https://raw.githubusercontent.com/LilDrunkenSmurf/k3s-home-cluster/main/icons/${each.value}.png"
  policy_engine_mode = "all"
}

resource "authentik_provider_proxy" "infra_proxy" {
  for_each              = local.infra_applications
  name                  = "${each.value}-provider"
  external_host         = "http://${each.value}.${data.sops_file.authentik_secrets.data["cluster_domain"]}"
  mode                  = "forward_single"
  authorization_flow    = resource.authentik_flow.provider-authorization-implicit-consent.uuid
  access_token_validity = "hours=24"
}

resource "authentik_application" "infra_application" {
  for_each           = local.infra_applications
  name               = title(each.value)
  slug               = authentik_provider_proxy.infra_proxy[each.value].name
  protocol_provider  = authentik_provider_proxy.infra_proxy[each.value].id
  group              = authentik_group.infrastructure.name
  open_in_new_tab    = true
  meta_icon          = "https://raw.githubusercontent.com/LilDrunkenSmurf/k3s-home-cluster/main/icons/${each.value}.png"
  policy_engine_mode = "all"
}

resource "authentik_outpost" "proxyoutpost" {
  name               = "proxy-outpost"
  type               = "proxy"
  service_connection = authentik_service_connection_kubernetes.local.id
  protocol_providers = local.proxy_list
  config = jsonencode({
    authentik_host          = "https://authentik.${data.sops_file.authentik_secrets.data["cluster_domain"]}",
    authentik_host_insecure = false,
    authentik_host_browser  = "",
    log_level               = "debug",
    object_naming_template  = "ak-outpost-%(name)s",
    docker_network          = null,
    docker_map_ports        = true,
    docker_labels           = null,
    container_image         = null,
    kubernetes_replicas     = 1,
    kubernetes_namespace    = "security",
    kubernetes_ingress_annotations = {
      "cert-manager.io/cluster-issuer" = "letsencrypt-production"
    },
    kubernetes_ingress_secret_name = "proxy-outpost-tls",
    kubernetes_service_type        = "ClusterIP",
    kubernetes_disabled_components = [],
    kubernetes_image_pull_secrets  = []
  })
}
