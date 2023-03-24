terraform {
  required_providers {
    authentik = {
      source  = "goauthentik/authentik"
      version = "2023.3.0"
    }
  }
}

provider "authentik" {
  url   = "https://authentik.lildrunkensmurf.com"
  token = var.authentik_bootstrap_token
}

data "authentik_certificate_key_pair" "generated" {
  name = "authentik Self-signed Certificate"
}
