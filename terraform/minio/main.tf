terraform {
  required_providers {
    onepassword = {
      source  = "1Password/onepassword"
      version = "2.1.2"
    }

    minio = {
      source  = "aminueza/minio"
      version = "3.3.0"
    }
  }
}

provider "onepassword" {
  url   = var.onepassword_connect
  token = var.service_account_json
}

data "onepassword_vault" "kubernetes" {
  name = "Kubernetes"
}

module "onepassword_minio" {
  source = "github.com/joryirving/terraform-1password-item"
  vault  = data.onepassword_vault.kubernetes.name
  item   = "minio"
}

provider "minio" {
  minio_server   = var.minio_url
  minio_user     = module.onepassword_minio.fields["MINIO_ACCESS_KEY"]
  minio_password = module.onepassword_minio.fields["MINIO_SECRET_KEY"]
  minio_ssl      = true
}
