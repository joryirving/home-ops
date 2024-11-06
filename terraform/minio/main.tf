terraform {
  required_providers {
    bitwarden = {
      source  = "maxlaverse/bitwarden"
      version = ">= 0.11.0"
    }

    minio = {
      source  = "aminueza/minio"
      version = ">= 2.5.1"
    }
  }
}

provider "bitwarden" {
  access_token = var.bw_access_token
  experimental {
    embedded_client = true
  }
}
data "bitwarden_secret" "minio" {
  key = "minio"
}

locals {
  minio_access_key = regex("MINIO_ACCESS_KEY: (\\S+)", data.bitwarden_secret.minio.value)
  minio_secret_key = regex("MINIO_SECRET_KEY: (\\S+)", data.bitwarden_secret.minio.value)
}

provider "minio" {
  minio_server   = var.minio_url
  minio_user     = local.minio_access_key[0]
  minio_password = local.minio_secret_key[0]
  minio_ssl      = true
}
