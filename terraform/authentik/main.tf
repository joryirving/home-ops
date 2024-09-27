terraform {
  required_providers {
    authentik = {
      source  = "goauthentik/authentik"
      version = "2024.8.4"
    }
  }
}

provider "authentik" {
  url   = "https://sso.${var.cluster_domain}"
  token = var.authentik_token
}
