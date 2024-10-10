resource "bitwarden_secret" "item" {
  key        = var.name
  note       = "Token for ${var.name}"
  project_id = var.bw_proj_id
  value      = "AWS_ACCESS_KEY_ID: ${var.username}\nAWS_SECRET_ACCESS_KEY: ${var.password}"
}
