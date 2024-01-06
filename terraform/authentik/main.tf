terraform {
  required_providers {
    authentik = {
      source  = "goauthentik/authentik"
      version = "2023.10.0"
    }
  }
}

provider "authentik" {
  url   = "https://authentik.${var.cluster_domain}"
  token = var.authentik_token
}
