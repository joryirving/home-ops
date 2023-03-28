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
  authentication_flow = data.authentik_flow.default-authorization-flow.id
  enrollment_flow     = data.authentik_flow.default-authorization-flow.id

  provider_type   = "discord"
  consumer_key    = var.client_id
  consumer_secret = var.client_secret
}
