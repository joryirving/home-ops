terraform {
  required_providers {
    onepassword = {
      source  = "1Password/onepassword"
      version = "2.2.1"
    }

    uptimerobot = {
      source  = "uptimerobot/uptimerobot"
      version = "1.3.0"
    }
  }
}

provider "onepassword" {
  url   = var.OP_CONNECT_HOST
  token = var.OP_CONNECT_TOKEN
}

data "onepassword_vault" "kubernetes" {
  name = "Kubernetes"
}

module "onepassword_uptimerobot" {
  source = "github.com/joryirving/terraform-1password-item"
  vault  = data.onepassword_vault.kubernetes.name
  item   = "uptimerobot"
}

provider "uptimerobot" {
  api_key = module.onepassword_uptimerobot.fields["UPTIMEROBOT_API_KEY"]
}
