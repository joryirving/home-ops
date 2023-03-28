resource "authentik_outpost" "proxyoutpost" {
  name               = "proxy-outpost"
  type               = "proxy"
  service_connection = authentik_service_connection_kubernetes.local.id
  protocol_providers = [
    for s in local.applications : authentik_provider_proxy.proxy[s].id
  ]
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

locals {
  applications = toset([
    "qbittorent",
    "prowlarr",
    "sonarr",
    "radarr",
    "readarr",
    "hajimari"
  ])
}

resource "authentik_provider_proxy" "proxy" {
  for_each              = local.applications
  name                  = "${each.value}-provider"
  external_host         = "http://${each.value}.${data.sops_file.authentik_secrets.data["cluster_domain"]}"
  mode                  = "forward_single"
  authorization_flow    = resource.authentik_flow.provider-authorization-implicit-consent.uuid
  access_token_validity = "hours=24"
}

resource "authentik_application" "application" {
  for_each           = local.applications
  name               = title(each.value)
  slug               = authentik_provider_proxy.proxy[each.value].name
  protocol_provider  = authentik_provider_proxy.proxy[each.value].id
  group              = authentik_group.media.name
  open_in_new_tab    = true
  meta_icon          = "https://${each.value}.lildrunkensmurf.com/Content/Images/logo.svg"
  policy_engine_mode = "all"
}
