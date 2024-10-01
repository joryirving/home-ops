terraform {
  required_providers {
    bitwarden = {
      source  = "maxlaverse/bitwarden"
      version = ">= 0.9.0"
    }
  }
}

data "bitwarden_item_login" "item" {
  id = var.id
}
