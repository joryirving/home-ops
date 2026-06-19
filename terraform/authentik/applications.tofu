locals {
  oauth_apps = [
    "autobrr",
    "Arcane",
    "Dispatch",
    "ErsatzTV",
    "Grafana",
    "Headlamp",
    "Kyoo",
    "LiteLLM",
    "Matrix",
    "Miso-Chat",
    "Miso-Gallery",
    "Open-WebUI",
    "Paperless",
    "Portainer",
    "RomM",
    "WorkAdventure",
  ]

  default_property_mappings = data.authentik_property_mapping_provider_scope.oauth2.ids
}

module "onepassword_application" {
  for_each = toset(local.oauth_apps)
  source   = "github.com/joryirving/terraform-1password-item"
  vault    = "Kubernetes"
  item     = lower(each.key)
}

locals {
  applications = {
    autobrr = {
      client_id         = module.onepassword_application["autobrr"].fields["AUTOBRR_CLIENT_ID"]
      client_secret     = module.onepassword_application["autobrr"].fields["AUTOBRR_CLIENT_SECRET"]
      group             = "media"
      icon_url          = "https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/png/autobrr.png"
      redirect_uri      = "https://autobrr.${var.CLUSTER_DOMAIN}/api/auth/oidc/callback"
      launch_url        = "https://autobrr.${var.CLUSTER_DOMAIN}"
      property_mappings = local.default_property_mappings
    },
    Arcane = {
      client_id         = module.onepassword_application["Arcane"].fields["ARCANE_CLIENT_ID"]
      client_secret     = module.onepassword_application["Arcane"].fields["ARCANE_CLIENT_SECRET"]
      group             = "media"
      icon_url          = "https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/png/arcane.png"
      redirect_uri      = "https://arcane.${var.CLUSTER_DOMAIN}/auth/oidc/callback"
      launch_url        = "https://arcane.${var.CLUSTER_DOMAIN}"
      property_mappings = local.default_property_mappings
    },
    Dispatch = {
      client_id         = module.onepassword_application["Dispatch"].fields["DISPATCH_CLIENT_ID"]
      client_secret     = module.onepassword_application["Dispatch"].fields["DISPATCH_CLIENT_SECRET"]
      group             = "ai"
      icon_url          = "https://avatars.githubusercontent.com/u/263493777?v=4"
      redirect_uri      = "https://dispatch.${var.CLUSTER_DOMAIN}/api/auth/callback/oidc"
      launch_url        = "https://dispatch.${var.CLUSTER_DOMAIN}"
      property_mappings = local.default_property_mappings
    },
    ErsatzTV = {
      client_id         = module.onepassword_application["ErsatzTV"].fields["ERSATZTV_CLIENT_ID"]
      client_secret     = module.onepassword_application["ErsatzTV"].fields["ERSATZTV_CLIENT_SECRET"]
      group             = "media"
      icon_url          = "https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/png/ersatztv.png"
      redirect_uri      = "https://tv.${var.CLUSTER_DOMAIN}/callback"
      launch_url        = "https://tv.${var.CLUSTER_DOMAIN}"
      property_mappings = local.default_property_mappings
    },
    Grafana = {
      client_id         = module.onepassword_application["Grafana"].fields["GRAFANA_CLIENT_ID"]
      client_secret     = module.onepassword_application["Grafana"].fields["GRAFANA_CLIENT_SECRET"]
      group             = "monitoring"
      icon_url          = "https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/png/grafana.png"
      redirect_uri      = "https://grafana.${var.CLUSTER_DOMAIN}/login/generic_oauth"
      launch_url        = "https://grafana.${var.CLUSTER_DOMAIN}/login/generic_oauth"
      property_mappings = local.default_property_mappings
    },
    Headlamp = {
      client_id         = module.onepassword_application["Headlamp"].fields["HEADLAMP_CLIENT_ID"]
      client_secret     = module.onepassword_application["Headlamp"].fields["HEADLAMP_CLIENT_SECRET"]
      group             = "infrastructure"
      icon_url          = "https://raw.githubusercontent.com/headlamp-k8s/headlamp/refs/heads/main/frontend/src/resources/icon-dark.svg"
      redirect_uri      = "https://headlamp.${var.CLUSTER_DOMAIN}/oidc-callback"
      launch_url        = "https://headlamp.${var.CLUSTER_DOMAIN}/"
      property_mappings = local.default_property_mappings
    },
    Matrix = {
      client_id         = module.onepassword_application["Matrix"].fields["MATRIX_CLIENT_ID"]
      client_secret     = module.onepassword_application["Matrix"].fields["MATRIX_CLIENT_SECRET"]
      group             = "workadventure"
      icon_url          = "https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/png/matrix.png"
      redirect_uri      = "https://matrix.${var.CLUSTER_DOMAIN}/_synapse/client/oidc/callback"
      launch_url        = "https://matrix.${var.CLUSTER_DOMAIN}"
      grant_types       = ["authorization_code"]
      property_mappings = local.default_property_mappings
    },
    Kyoo = {
      client_id         = module.onepassword_application["Kyoo"].fields["KYOO_CLIENT_ID"]
      client_secret     = module.onepassword_application["Kyoo"].fields["KYOO_CLIENT_SECRET"]
      group             = "media"
      icon_url          = "https://raw.githubusercontent.com/zoriya/Kyoo/master/icons/icon-256x256.png"
      redirect_uri      = "https://kyoo.${var.CLUSTER_DOMAIN}/api/auth/logged/authentik"
      launch_url        = "https://kyoo.${var.CLUSTER_DOMAIN}/api/auth/login/authentik?redirectUrl=https://kyoo.${var.CLUSTER_DOMAIN}/login/callback"
      property_mappings = local.default_property_mappings
    },
    LiteLLM = {
      client_id         = module.onepassword_application["LiteLLM"].fields["LITELLM_CLIENT_ID"]
      client_secret     = module.onepassword_application["LiteLLM"].fields["LITELLM_CLIENT_SECRET"]
      group             = "ai"
      icon_url          = "https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/png/litellm.png"
      redirect_uri      = "https://litellm.${var.CLUSTER_DOMAIN}/sso/callback"
      launch_url        = "https://litellm.${var.CLUSTER_DOMAIN}/ui"
      property_mappings = local.default_property_mappings
    },
    Miso-Chat = {
      client_id         = module.onepassword_application["Miso-Chat"].fields["MISO_CHAT_CLIENT_ID"]
      client_secret     = module.onepassword_application["Miso-Chat"].fields["MISO_CHAT_CLIENT_SECRET"]
      group             = "ai"
      icon_url          = "https://avatars.githubusercontent.com/u/263493777?v=4"
      redirect_uri      = "https://miso-chat.${var.CLUSTER_DOMAIN}/auth/oidc/callback"
      launch_url        = "https://miso-chat.${var.CLUSTER_DOMAIN}/auth/oidc"
      property_mappings = local.default_property_mappings
    },
    Miso-Gallery = {
      client_id         = module.onepassword_application["Miso-Gallery"].fields["MISO_GALLERY_CLIENT_ID"]
      client_secret     = module.onepassword_application["Miso-Gallery"].fields["MISO_GALLERY_CLIENT_SECRET"]
      group             = "ai"
      icon_url          = "https://raw.githubusercontent.com/joryirving/miso-gallery/main/assets/miso-gallery-logo.png"
      redirect_uri      = "https://miso-gallery.${var.CLUSTER_DOMAIN}/auth/oidc/callback"
      launch_url        = "https://miso-gallery.${var.CLUSTER_DOMAIN}/auth/oidc"
      property_mappings = local.default_property_mappings
    },
    Open-WebUI = {
      client_id         = module.onepassword_application["Open-WebUI"].fields["OPEN_WEBUI_CLIENT_ID"]
      client_secret     = module.onepassword_application["Open-WebUI"].fields["OPEN_WEBUI_CLIENT_SECRET"]
      group             = "ai"
      icon_url          = "https://raw.githubusercontent.com/open-webui/open-webui/refs/heads/main/static/favicon.png"
      redirect_uri      = "https://chat.${var.CLUSTER_DOMAIN}/oauth/oidc/callback"
      launch_url        = "https://chat.${var.CLUSTER_DOMAIN}/auth"
      property_mappings = local.default_property_mappings
    },
    Paperless = {
      client_id         = module.onepassword_application["Paperless"].fields["PAPERLESS_CLIENT_ID"]
      client_secret     = module.onepassword_application["Paperless"].fields["PAPERLESS_CLIENT_SECRET"]
      group             = "home"
      icon_url          = "https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/png/paperless.png"
      redirect_uri      = "https://paperless.${var.CLUSTER_DOMAIN}/accounts/oidc/authentik/login/callback/"
      launch_url        = "https://paperless.${var.CLUSTER_DOMAIN}/"
      property_mappings = local.default_property_mappings
    },
    Portainer = {
      client_id         = module.onepassword_application["Portainer"].fields["PORTAINER_CLIENT_ID"]
      client_secret     = module.onepassword_application["Portainer"].fields["PORTAINER_CLIENT_SECRET"]
      group             = "infrastructure"
      icon_url          = "https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/png/portainer.png"
      redirect_uri      = "https://portainer.${var.CLUSTER_DOMAIN}/"
      launch_url        = "https://portainer.${var.CLUSTER_DOMAIN}/"
      property_mappings = local.default_property_mappings
    },
    RomM = {
      client_id         = module.onepassword_application["RomM"].fields["ROMM_OIDC_CLIENT_ID"]
      client_secret     = module.onepassword_application["RomM"].fields["ROMM_OIDC_CLIENT_SECRET"]
      group             = "games"
      icon_url          = "https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/png/romm.png"
      redirect_uri      = "https://romm.${var.CLUSTER_DOMAIN}/api/oauth/openid"
      launch_url        = "https://romm.${var.CLUSTER_DOMAIN}"
      property_mappings = concat(local.default_property_mappings, [authentik_property_mapping_provider_scope.email_verified.id])
    },
    WorkAdventure = {
      client_id         = module.onepassword_application["WorkAdventure"].fields["WORKADVENTURE_OIDC_CLIENT_ID"]
      client_secret     = module.onepassword_application["WorkAdventure"].fields["WORKADVENTURE_OIDC_CLIENT_SECRET"]
      group             = "workadventure"
      icon_url          = "https://raw.githubusercontent.com/workadventure/workadventure/refs/heads/master/play/public/static/images/favicons/icon-512x512.png"
      redirect_uri      = "https://gather.${var.CLUSTER_DOMAIN}/openid-callback"
      launch_url        = "https://gather.${var.CLUSTER_DOMAIN}"
      property_mappings = local.default_property_mappings
    },
  }
}

resource "authentik_provider_oauth2" "oauth2" {
  for_each              = local.applications
  name                  = each.key
  client_id             = each.value.client_id
  client_secret         = each.value.client_secret
  authorization_flow    = authentik_flow.provider-authorization-implicit-consent.uuid
  authentication_flow   = authentik_flow.authentication.uuid
  invalidation_flow     = data.authentik_flow.default-provider-invalidation-flow.id
  property_mappings     = each.value.property_mappings
  access_token_validity = "hours=4"
  signing_key           = data.authentik_certificate_key_pair.generated.id
  allowed_redirect_uris = concat(
    [
      {
        matching_mode = "strict",
        redirect_uri_type = "authorization",
        url           = each.value.redirect_uri,
      },
    ],
    try(each.value.additional_redirect_uris, [])
  )
  # grant_types = try(each.value.grant_types, [])
}

resource "authentik_application" "application" {
  for_each           = local.applications
  name               = each.key
  slug               = lower(each.key)
  protocol_provider  = authentik_provider_oauth2.oauth2[each.key].id
  group              = authentik_group.default[each.value.group].name
  open_in_new_tab    = true
  meta_icon          = each.value.icon_url
  meta_launch_url    = each.value.launch_url
  policy_engine_mode = "all"
}
