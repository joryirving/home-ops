terraform {
  required_providers {
    authentik = {
      source  = "goauthentik/authentik"
      version = ">= 2024.10.0"
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

data "bitwarden_secret" "authentik" {
  key = "authentik"
}

locals {
  authentik_token = regex("AUTHENTIK_TOKEN: (\\S+)", data.bitwarden_secret.authentik.value)[0]
}

provider "authentik" {
  url   = "https://sso.${var.cluster_domain}"
  token = local.authentik_token
}
