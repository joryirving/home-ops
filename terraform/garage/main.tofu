terraform {
  required_providers {
    onepassword = {
      source  = "1Password/onepassword"
      version = "3.2.0"
    }

    garage = {
      source  = "schwitzd/garage"
      version = "1.2.2"
    }
  }
}

# 1Password provider for secure credential retrieval
provider "onepassword" {
  connect_url   = var.OP_CONNECT_HOST
  connect_token = var.OP_CONNECT_TOKEN
}

# Data source to reference the Kubernetes vault
data "onepassword_vault" "kubernetes" {
  name = "Kubernetes"
}

# Module to retrieve garage credentials from 1Password
module "onepassword_garage" {
  source = "github.com/joryirving/terraform-1password-item"
  vault  = data.onepassword_vault.kubernetes.name
  item   = "garage"

  providers = {
    onepassword = onepassword
  }
}

# Garage provider configuration using credentials from 1Password
provider "garage" {
  host  = var.GARAGE_URL
  token = module.onepassword_garage.fields["GARAGE_ADMIN_TOKEN"]
}

