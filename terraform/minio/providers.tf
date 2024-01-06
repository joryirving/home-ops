provider "bitwarden" {
  master_password = var.bw_password
  client_id       = var.bw_client_id
  client_secret   = var.bw_client_secret
  email           = var.bw_email
}

provider "minio" {
  minio_server   = var.minio_url
  minio_user     = module.secrets_s3.data.access-key
  minio_password = module.secrets_s3.data.secret-key
}
