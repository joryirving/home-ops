terraform {
  required_providers {
    authentik = {
      source  = "goauthentik/authentik"
      version = ">= 2024.10.0"
    }

    onepassword = {
      source  = "1Password/onepassword"
      version = ">= 2.1.2"
    }

    bitwarden = {
      source  = "maxlaverse/bitwarden"
      version = ">= 0.11.0"
    }
  }
}

provider "bitwarden" {
  access_token = var.bw_access_token
  experimental {
    embedded_client = true
  }
}

provider "onepassword" {
  service_account_token = var.onepassword_sa_token
}

module "onepassword_authentik" {
  source = "github.com/joryirving/terraform-1password-item"
  vault  = "Kubernetes"
  item   = "authentik"
}

provider "authentik" {
  url   = "https://sso.${var.cluster_domain}"
  token = module.onepassword_authentik.fields["AUTHENTIK_TOKEN"]
}
