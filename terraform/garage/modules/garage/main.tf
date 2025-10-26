terraform {
  required_providers {
    garage = {
      source  = "schwitzd/garage"
      version = "1.2.1"
    }
  }
}

resource "garage_bucket" "bucket" {
  global_alias = var.bucket_name
}

resource "garage_key" "access_key" {
  name = "${var.bucket_name}-key"
}

resource "garage_bucket_key" "bucket_key" {
  access_key_id = garage_key.access_key.id
  bucket_id     = garage_bucket.bucket.id
  owner         = true
  read          = true
  write         = true
}

resource "garage_bucket_key" "admin_user" {
  access_key_id = var.admin_user
  bucket_id     = garage_bucket.bucket.id
  owner         = true
  read          = true
  write         = true
}
