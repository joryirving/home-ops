locals {
  # Define buckets that should be managed by garage
  # Each bucket will be created using the garage module
  buckets = [
    "postgresql"     # Database backups and persistent storage
  ]
}

# Admin key for managing garage buckets
resource "garage_key" "admin_key" {
  name = "admin-user"
}

# Create buckets dynamically using the garage module
module "buckets" {
  for_each    = toset(local.buckets)
  source      = "./modules/garage"
  bucket_name = each.key
  admin_user  = garage_key.admin_key.id

  providers = {
    garage = garage
  }
}

