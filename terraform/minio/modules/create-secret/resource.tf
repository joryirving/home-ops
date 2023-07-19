resource "bitwarden_item_login" "item" {
  name     = var.name
  username = var.username
  password = var.password
}
