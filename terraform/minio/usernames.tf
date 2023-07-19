resource "random_password" "user_name" {
  for_each = toset(local.buckets)
  length   = 32
  special  = false
}

resource "random_password" "user_secret" {
  for_each = toset(local.buckets)
  length   = 32
}
