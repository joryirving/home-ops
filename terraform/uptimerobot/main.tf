terraform {
  required_providers {
    uptimerobot = {
      source  = "uptimerobot/uptimerobot"
      version = "1.3.1"
    }
  }
}

provider "uptimerobot" {
  api_key = var.uptimerobot_api_key
}
