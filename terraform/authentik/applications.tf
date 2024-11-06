locals {
  oauth_apps = [
    "grafana",
    "headscale",
    "kyoo",
    "lubelog",
    "paperless",
    "portainer"
  ]
}

# Step 1: Retrieve secrets from Bitwarden
data "bitwarden_secret" "application" {
  for_each = toset(local.oauth_apps)
  key      = each.key
}

# Step 2: Parse the secrets using regex to extract client_id and client_secret
locals {
  parsed_secrets = {
    for app, secret in data.bitwarden_secret.application : app => {
      client_id     = replace(regex(".*_CLIENT_ID: (\\S+)", secret.value)[0], "\"", "")
      client_secret = replace(regex(".*_CLIENT_SECRET: (\\S+)", secret.value)[0], "\"", "")
    }
  }
}

locals {
  applications = {
    grafana = {
      client_id     = local.parsed_secrets["grafana"].client_id
      client_secret = local.parsed_secrets["grafana"].client_secret
      group         = authentik_group.monitoring.name
      icon_url      = "https://raw.githubusercontent.com/walkxcode/dashboard-icons/main/png/grafana.png"
      redirect_uri  = "https://grafana.${var.cluster_domain}/login/generic_oauth"
      launch_url    = "https://grafana.${var.cluster_domain}/login/generic_oauth"
    },
    headscale = {
      client_id     = local.parsed_secrets["headscale"].client_id
      client_secret = local.parsed_secrets["headscale"].client_secret
      group         = authentik_group.infrastructure.name
      icon_url      = "https://raw.githubusercontent.com/joryirving/home-ops/main/docs/src/assets/icons/headscale.png"
      redirect_uri  = "https://headscale.${var.cluster_domain}/oidc/callback"
      launch_url    = "https://headscale.${var.cluster_domain}/"
    },
    kyoo = {
      client_id     = local.parsed_secrets["kyoo"].client_id
      client_secret = local.parsed_secrets["kyoo"].client_secret
      group         = authentik_group.home.name
      icon_url      = "https://raw.githubusercontent.com/zoriya/Kyoo/master/icons/icon-256x256.png"
      redirect_uri  = "https://kyoo.${var.cluster_domain}/api/auth/logged/authentik"
      launch_url    = "https://kyoo.${var.cluster_domain}/api/auth/login/authentik?redirectUrl=https://kyoo.${var.cluster_domain}/login/callback"
    },
    lubelog = {
      client_id     = local.parsed_secrets["lubelog"].client_id
      client_secret = local.parsed_secrets["lubelog"].client_secret
      group         = authentik_group.home.name
      icon_url      = "https://demo.lubelogger.com/defaults/lubelogger_icon_72.png"
      redirect_uri  = "https://lubelog.${var.cluster_domain}/Login/RemoteAuth"
      launch_url    = "https://lubelog.${var.cluster_domain}/Login/RemoteAuth"
    },
    paperless = {
      client_id     = local.parsed_secrets["paperless"].client_id
      client_secret = local.parsed_secrets["paperless"].client_secret
      group         = authentik_group.home.name
      icon_url      = "https://raw.githubusercontent.com/walkxcode/dashboard-icons/main/png/paperless.png"
      redirect_uri  = "https://paperless.${var.cluster_domain}/accounts/oidc/authentik/login/callback/"
      launch_url    = "https://paperless.${var.cluster_domain}/"
    },
    portainer = {
      client_id     = local.parsed_secrets["portainer"].client_id
      client_secret = local.parsed_secrets["portainer"].client_secret
      group         = authentik_group.infrastructure.name
      icon_url      = "https://raw.githubusercontent.com/walkxcode/dashboard-icons/main/png/portainer.png"
      redirect_uri  = "https://portainer.${var.cluster_domain}/"
      launch_url    = "https://portainer.${var.cluster_domain}/"
    }
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
  property_mappings     = data.authentik_property_mapping_provider_scope.oauth2.ids
  access_token_validity = "hours=4"
  signing_key           = data.authentik_certificate_key_pair.generated.id
  redirect_uris         = [each.value.redirect_uri]
}

resource "authentik_application" "application" {
  for_each           = local.applications
  name               = title(each.key)
  slug               = each.key
  protocol_provider  = authentik_provider_oauth2.oauth2[each.key].id
  group              = each.value.group
  open_in_new_tab    = true
  meta_icon          = each.value.icon_url
  meta_launch_url    = each.value.launch_url
  policy_engine_mode = "all"
}
