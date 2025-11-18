resource "uptimerobot_integration" "taco_time" {
  name                     = "Taco Time"
  type                     = "discord"
  value                    = var.taco_time_discord_webhook_url
  enable_notifications_for = 1
  ssl_expiration_reminder  = true
}
