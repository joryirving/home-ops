provider "bitwarden" {
  master_password = var.BW_PASSWORD
  client_id       = var.BW_CLIENTID
  client_secret   = var.BW_CLIENTSECRET
}

provider "minio" {
  minio_server   = "minio.${var.SECRET_DOMAIN}"
  minio_user     = module.secrets_s3.data.access-key
  minio_password = module.secrets_s3.data.secret-key
}
