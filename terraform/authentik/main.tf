terraform {
  required_providers {
    authentik = {
      source  = "goauthentik/authentik"
      version = "2025.10.1"
    }

    onepassword = {
      source  = "1password/onepassword"
      version = "3.0.1"
    }
  }
}

provider "onepassword" {
  connect_url   = var.OP_CONNECT_HOST
  connect_token = var.OP_CONNECT_TOKEN
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
