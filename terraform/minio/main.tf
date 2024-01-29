locals {
  buckets = [
    "longhorn",
    "postgresql",
    "volsync"
  ]
}

terraform {
  required_providers {
    bitwarden = {
      source  = "maxlaverse/bitwarden"
      version = ">= 0.7.0"
    }

    minio = {
      source  = "aminueza/minio"
      version = ">= 2.0.1"
    }
  }
}

module "secrets_s3" {
  source = "./modules/get-secret"
  id     = "5a98804c-6c54-4e09-817e-afd8012c70ad"
}
