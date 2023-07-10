resource "authentik_group" "users" {
  name         = "users"
  is_superuser = false
}

resource "authentik_group" "downloads" {
  name         = "Downloads"
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

resource "authentik_group" "media" {
  name         = "Media"
  is_superuser = false
  parent       = resource.authentik_group.users.id
}

resource "authentik_group" "grafana_admin" {
  name         = "Grafana Admins"
  is_superuser = false
}

resource "authentik_group" "monitoring" {
  name         = "Monitoring"
  is_superuser = false
  parent       = resource.authentik_group.grafana_admin.id
}

data "authentik_group" "admins" {
  name = "authentik Admins"
}

##Oauth
resource "authentik_source_oauth" "discord" {
  name                = "Discord"
  slug                = "discord"
  authentication_flow = authentik_flow.authentication.id
  enrollment_flow     = authentik_flow.enrollment-invitation.id
  user_matching_mode  = "email_link"

  provider_type   = "discord"
  consumer_key    = data.sops_file.authentik_secrets.data["discord_client_id"]
  consumer_secret = data.sops_file.authentik_secrets.data["discord_client_secret"]
}