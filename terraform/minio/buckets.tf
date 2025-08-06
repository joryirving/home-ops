locals {
  buckets = [
    "postgresql"
  ]
}

module "buckets" {
  for_each    = toset(local.buckets)
  source      = "./modules/minio"
  bucket_name = each.key
  user_name   = random_password.user_name[each.key].result
  user_secret = random_password.user_secret[each.key].result

  providers = {
    minio = minio
  }
}
