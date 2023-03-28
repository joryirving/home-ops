resource "authentik_group" "users" {
  name         = "users"
  is_superuser = false
}

resource "authentik_group" "media" {
  name         = "media"
  is_superuser = false
  parent       = resource.authentik_group.users.id
}

resource "authentik_group" "infrastructure" {
  name         = "infrastructure"
  is_superuser = false
}

data "authentik_group" "admins" {
  name = "authentik Admins"
}

resource "authentik_source_oauth" "discord" {
  name                = "discord"
  slug                = "discord"
  authentication_flow = resource.authentik_flow.provider-authorization-implicit-consent.uuid
  enrollment_flow     = resource.authentik_flow.provider-authorization-implicit-consent.uuid

  provider_type   = "discord"
  consumer_key    = data.sops_file.authentik_secrets.data["discord_client_id"]
  consumer_secret = data.sops_file.authentik_secrets.data["discord_client_secret"]
}
