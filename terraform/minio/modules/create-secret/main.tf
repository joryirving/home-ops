resource "onepassword_item" "item" {
  vault    = var.onepassword_vault
  title    = var.name
  category = "login"
  username = var.username
  password = var.password

  section {
    label = "Token for ${var.name}"
    field {
      label = "AWS_ACCESS_KEY_ID"
      type  = "STRING"
      value = var.username
    }
    field {
      label = "AWS_SECRET_ACCESS_KEY"
      type  = "CONCEALED"
      value = var.password
    }
  }
}
