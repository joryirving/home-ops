terraform {
  required_providers {
    authentik = {
      source  = "goauthentik/authentik"
      version = "2025.12.0"
    }

    onepassword = {
      source  = "1password/onepassword"
      version = "3.1.2"
    }
  }
}

# 1Password provider for secure credential retrieval
provider "onepassword" {
  connect_url   = var.OP_CONNECT_HOST
  connect_token = var.OP_CONNECT_TOKEN
}

# Module to retrieve authentik credentials from 1Password
module "onepassword_authentik" {
  source = "github.com/joryirving/terraform-1password-item"
  vault  = "Kubernetes"
  item   = "authentik"
}

# Authentik provider configuration using credentials from 1Password
provider "authentik" {
  url   = "https://sso.${var.CLUSTER_DOMAIN}"
  token = module.onepassword_authentik.fields["AUTHENTIK_TOKEN"]
}

