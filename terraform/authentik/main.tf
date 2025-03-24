terraform {
  required_providers {
    authentik = {
      source  = "goauthentik/authentik"
      version = "2025.2.0"
    }

    onepassword = {
      source  = "1Password/onepassword"
      version = "2.1.2"
    }
  }
}

provider "onepassword" {
  url   = var.OP_CONNECT_HOST
  token = var.OP_CONNECT_TOKEN
}

module "onepassword_authentik" {
  source = "github.com/joryirving/terraform-1password-item"
  vault  = "Kubernetes"
  item   = "authentik"
}

provider "authentik" {
  url   = "https://sso.${var.CLUSTER_DOMAIN}"
  token = module.onepassword_authentik.fields["AUTHENTIK_TOKEN"]
}
