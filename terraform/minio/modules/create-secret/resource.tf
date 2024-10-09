# resource "bitwarden_item_login" "item" {
#   name     = var.name
#   username = var.username
#   password = var.password
# }

resource "bitwarden_secret" "item" {
  key        = var.name
  note       = "Token for ${var.name}"
  project_id = var.bw_proj_id
  value      = "AWS_SECRET_ACCESS_KEY=${var.username}\nAWS_SECRET_ACCESS_KEY=${var.password}"
}
