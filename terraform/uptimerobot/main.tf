terraform {
  required_providers {
    uptimerobot = {
      source  = "uptimerobot/uptimerobot"
      version = "1.3.0"
    }
  }
}

provider "uptimerobot" {
  api_key = var.uptimerobot_api_key
}

resource "uptimerobot_monitor" "plex" {
  name     = "Plex"
  type     = "HTTP"
  url      = "https://plex.jory.dev/web/index.html"

  check_ssl_errors = true
  interval = 300
  follow_redirections = true
  timeout = 30
}

resource "uptimerobot_monitor" "seerr" {
  name     = "Seerr"
  type     = "HTTP"
  url      = "https://requests.jory.dev"

  check_ssl_errors = true
  interval = 300
  follow_redirections = true
  timeout = 30
}

resource "uptimerobot_monitor" "gatus" {
  name     = "Status Page"
  type     = "HTTP"
  url      = "https://status.jory.dev"

  check_ssl_errors = true
  interval = 300
  follow_redirections = true
  timeout = 30
}

import {
  to = uptimerobot_monitor.plex
  id = "795945113"
}

import {
  to = uptimerobot_monitor.seerr
  id = "795945114"
}

import {
  to = uptimerobot_monitor.gatus
  id = "795944990"
}
