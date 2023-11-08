terraform {
  required_providers {
    sops = {
      source  = "carlpett/sops"
      version = "1.0.0"
    }
    authentik = {
      source  = "goauthentik/authentik"
      version = "2023.10.0"
    }
  }
}

data "sops_file" "authentik_secrets" {
  source_file = "secret.sops.yaml"
}

provider "authentik" {
  url   = data.sops_file.authentik_secrets.data["authentik_endpoint"]
  token = data.sops_file.authentik_secrets.data["authentik_token"]
}
