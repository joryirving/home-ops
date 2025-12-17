resource "authentik_stage_prompt_field" "username" {
  name                     = "username"
  field_key                = "username"
  required                 = true
  type                     = "text"
  label                    = "Username"
  initial_value            = "try:\n    return user.username\nexcept:\n    return ''"
  initial_value_expression = true
  placeholder              = "try:\n    return user.username\nexcept:\n    return ''"
  order                    = 200
}

resource "authentik_stage_prompt_field" "name" {
  name                     = "name"
  field_key                = "name"
  type                     = "text"
  required                 = true
  label                    = "Name"
  initial_value            = "try:\n    return user.name\nexcept:\n    return ''"
  initial_value_expression = true
  placeholder              = "try:\n    return user.name\nexcept:\n    return ''"
  order                    = 201
}

resource "authentik_stage_prompt_field" "email" {
  name                     = "email"
  field_key                = "email"
  type                     = "email"
  required                 = true
  label                    = "Email"
  initial_value            = "try:\n    return user.email\nexcept:\n    return ''"
  initial_value_expression = true
  placeholder              = "try:\n    return user.email\nexcept:\n    return ''"
  order                    = 202
}

resource "authentik_stage_prompt_field" "locale" {
  name                     = "locale"
  field_key                = "attributes.settings.locale"
  type                     = "ak-locale"
  required                 = true
  label                    = "Locale"
  initial_value            = "try:\n    return user.attributes.get('settings', {}).get('locale', '')\nexcept:\n    return ''"
  initial_value_expression = true
  placeholder              = "try:\n    return user.attributes.get('settings', {}).get('locale', '')\nexcept:\n    return ''"
  order                    = 203
}

resource "authentik_stage_prompt_field" "password" {
  name          = "password"
  field_key     = "password"
  type          = "password"
  label         = "Password"
  initial_value = "Password"
  placeholder   = "Password"
  required      = true
  order         = 300
}

resource "authentik_stage_prompt_field" "password-repeat" {
  name          = "password-repeat"
  field_key     = "password-repeat"
  type          = "password"
  label         = "Password (repeat)"
  initial_value = "Password (repeat)"
  placeholder   = "Password (repeat)"
  required      = true
  order         = 301
}
