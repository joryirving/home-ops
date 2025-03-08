terraform {
  required_providers {
    authentik = {
      source  = "goauthentik/authentik"
      version = "2024.12.1"
    }

    onepassword = {
      source  = "1Password/onepassword"
      version = "2.1.2"
    }
  }
}

provider "onepassword" {
  url   = var.onepassword_connect
  token = var.service_account_json
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
