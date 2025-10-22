locals {
  buckets = [
    "postgresql"
  ]
}

resource "garage_key" "admin_key" {
  name = "admin-user"
}

module "buckets" {
  for_each    = toset(local.buckets)
  source      = "./modules/garage"
  bucket_name = each.key
  admin_user  = garage_key.admin_key.id

  providers = {
    garage = garage
  }
}
