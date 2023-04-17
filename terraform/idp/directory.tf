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

resource "authentik_group" "monitoring" {
  name         = "Monitoring"
  is_superuser = false
}

data "authentik_group" "admins" {
  name = "authentik Admins"
}
