locals {
  buckets = [
    "loki",
    "longhorn",
    "postgresql",
    "thanos",
    "volsync"
  ]
}

terraform {
  required_providers {
    bitwarden = {
      source  = "maxlaverse/bitwarden"
      version = ">= 0.6.0"
    }

    sops = {
      source  = "carlpett/sops"
      version = "1.0.0"
    }

    minio = {
      source  = "aminueza/minio"
      version = "2.0.1"
    }
  }
}

data "sops_file" "bw_secrets" {
  source_file = "secret.sops.yaml"
}

module "secrets_s3" {
  source = "./modules/get-secret"
  id     = "5a98804c-6c54-4e09-817e-afd8012c70ad"
}
