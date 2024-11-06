
data "authentik_group" "admins" {
  name = "authentik Admins"
}

resource "authentik_group" "downloads" {
  name         = "Downloads"
  is_superuser = false
}

resource "authentik_group" "grafana_admin" {
  name         = "Grafana Admins"
  is_superuser = false
}

resource "authentik_group" "headscale" {
  name         = "Headscale"
  is_superuser = false
}

resource "authentik_group" "home" {
  name         = "Home"
  is_superuser = false
}

resource "authentik_group" "infrastructure" {
  name         = "Infrastructure"
  is_superuser = false
}

resource "authentik_group" "monitoring" {
  name         = "Monitoring"
  is_superuser = false
  parent       = resource.authentik_group.grafana_admin.id
}

resource "authentik_group" "users" {
  name         = "users"
  is_superuser = false
}

data "authentik_group" "lookup" {
  for_each = local.applications
  name     = each.value.group
}

resource "authentik_policy_binding" "application_policy_binding" {
  for_each = local.applications

  target = authentik_application.application[each.key].uuid
  group  = data.authentik_group.lookup[each.key].id
  order  = 0
}

data "bitwarden_secret" "discord" {
  key = "discord"
}

locals {
  discord_client_id     = regex("DISCORD_CLIENT_ID: (\\S+)", data.bitwarden_secret.discord.value)
  discord_client_secret = regex("DISCORD_CLIENT_SECRET: (\\S+)", data.bitwarden_secret.discord.value)
}

##Oauth
resource "authentik_source_oauth" "discord" {
  name                = "Discord"
  slug                = "discord"
  authentication_flow = data.authentik_flow.default-source-authentication.id
  enrollment_flow     = authentik_flow.enrollment-invitation.uuid
  user_matching_mode  = "email_deny"

  provider_type   = "discord"
  consumer_key    = local.discord_client_id[0]
  consumer_secret = local.discord_client_secret[0]
}
