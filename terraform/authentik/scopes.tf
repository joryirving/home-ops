## OAuth scopes
data "authentik_property_mapping_provider_scope" "oauth2" {
  managed_list = [
    "goauthentik.io/providers/oauth2/scope-openid",
    "goauthentik.io/providers/oauth2/scope-email",
    "goauthentik.io/providers/oauth2/scope-profile"
  ]
}

resource "authentik_property_mapping_provider_scope" "email_verified" {
  name       = "Email Verified Scope"
  scope_name = "email"
  expression = <<-EOT
    return {
      "email": user.email,
      "email_verified": True,
    }
  EOT
}
