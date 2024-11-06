data "bitwarden_secret" "bw_proj_id" {
  key = "BW_PROJ_ID"
}

module "secrets" {
  for_each   = toset(local.buckets)
  source     = "./modules/create-secret"
  name       = "${each.key}-bucket"
  username   = random_password.user_name[each.key].result
  password   = random_password.user_secret[each.key].result
  bw_proj_id = data.bitwarden_secret.bw_proj_id.value
}
