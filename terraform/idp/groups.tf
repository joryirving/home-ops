
resource "authentik_group" "admin" {
  name         = "admin"
  is_superuser = true
}

resource "authentik_group" "bind" {
  name         = "bind"
  is_superuser = false
}
