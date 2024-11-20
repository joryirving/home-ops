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
