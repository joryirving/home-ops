data "bitwarden_secret" "item" {
  id = var.bw_minio_secret_id
}

locals {
  minio_access_key = regex("MINIO_ACCESS_KEY: (\\S+)", data.bitwarden_secret.item.value)
  minio_secret_key = regex("MINIO_SECRET_KEY: (\\S+)", data.bitwarden_secret.item.value)
}
