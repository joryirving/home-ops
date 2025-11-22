resource "uptimerobot_integration" "taco_time" {
  name                     = "Taco Time"
  type                     = "discord"
  value                    = module.onepassword_uptimerobot.fields["DISCORD_WEBHOOK"]
  enable_notifications_for = 1
  ssl_expiration_reminder  = true
}
