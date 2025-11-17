terraform {
  required_providers {
    onepassword = {
      source  = "1Password/onepassword"
      version = "2.2.1"
    }

    garage = {
      source  = "schwitzd/garage"
      version = "1.2.2"
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

module "onepassword_garage" {
  source = "github.com/joryirving/terraform-1password-item"
  vault  = data.onepassword_vault.kubernetes.name
  item   = "garage"
}

provider "garage" {
  host  = var.GARAGE_URL
  token = module.onepassword_garage.fields["GARAGE_ADMIN_TOKEN"]
}
