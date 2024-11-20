terraform {
  required_providers {
    onepassword = {
      source  = "1Password/onepassword"
      version = ">= 2.1.2"
    }

    minio = {
      source  = "aminueza/minio"
      version = ">= 2.5.1"
    }
  }
}

provider "onepassword" {
  service_account_token = var.onepassword_sa_token
}

module "onepassword_minio" {
  source = "github.com/joryirving/terraform-1password-item"
  vault  = "Kubernetes"
  item   = "minio"
}

provider "minio" {
  minio_server   = var.minio_url
  minio_user     = module.onepassword_minio.fields["MINIO_ACCESS_KEY"]
  minio_password = module.onepassword_minio.fields["MINIO_SECRET_KEY"]
  minio_ssl      = true
}
