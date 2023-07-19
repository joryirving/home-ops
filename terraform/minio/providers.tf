provider "bitwarden" {
  master_password = data.sops_file.bw_secrets.data["bw_password"]
  client_id       = data.sops_file.bw_secrets.data["bw_client_id"]
  client_secret   = data.sops_file.bw_secrets.data["bw_client_secret"]
  email           = data.sops_file.bw_secrets.data["bw_email"]
}

provider "minio" {
  minio_server   = data.sops_file.bw_secrets.data["minio_url"]
  minio_user     = module.secrets_s3.data.access-key
  minio_password = module.secrets_s3.data.secret-key
}
