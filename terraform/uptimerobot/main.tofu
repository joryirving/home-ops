terraform {
  required_providers {
    onepassword = {
      source  = "1Password/onepassword"
      version = "3.1.2"
    }

    uptimerobot = {
      source  = "uptimerobot/uptimerobot"
      version = "1.3.9"
    }
  }
}

provider "onepassword" {
  connect_url   = var.OP_CONNECT_HOST
  connect_token = var.OP_CONNECT_TOKEN
}

data "onepassword_vault" "kubernetes" {
  name = "Kubernetes"
}

module "onepassword_uptimerobot" {
  source = "github.com/joryirving/terraform-1password-item"
  vault  = data.onepassword_vault.kubernetes.name
  item   = "uptimerobot"

  providers = {
    onepassword = onepassword
  }
}

provider "uptimerobot" {
  api_key = module.onepassword_uptimerobot.fields["UPTIMEROBOT_API_KEY"]
}
