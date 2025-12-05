module "secrets" {
  for_each          = toset(local.buckets)
  source            = "./modules/create-secret"
  name              = each.key
  username          = module.buckets[each.key].access_key_id
  password          = module.buckets[each.key].access_key_secret
  onepassword_vault = data.onepassword_vault.kubernetes.uuid
}

resource "onepassword_item" "admin_user" {
  vault    = data.onepassword_vault.kubernetes.uuid
  title    = "garage-admin"
  category = "login"
  username = garage_key.admin_key.access_key_id
  password = garage_key.admin_key.secret_access_key

  section {
    label = "Token for ${garage_key.admin_key.id}"
    field {
      label = "AWS_ACCESS_KEY_ID"
      type  = "STRING"
      value = garage_key.admin_key.access_key_id
    }
    field {
      label = "AWS_SECRET_ACCESS_KEY"
      type  = "CONCEALED"
      value = garage_key.admin_key.secret_access_key
    }
  }
}
