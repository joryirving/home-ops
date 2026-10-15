## OAuth scopes
data "authentik_property_mapping_provider_scope" "oauth2" {
  managed_list = [
    "goauthentik.io/providers/oauth2/scope-offline_access",
    "goauthentik.io/providers/oauth2/scope-openid",
    "goauthentik.io/providers/oauth2/scope-email",
    "goauthentik.io/providers/oauth2/scope-profile"
  ]
}

# The built-in OpenID 'email' mapping hardcodes email_verified=False; consumers
# that require a verified email exclude it and use Email Verified Scope instead
data "authentik_property_mapping_provider_scope" "email_builtin" {
  managed = "goauthentik.io/providers/oauth2/scope-email"
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

resource "authentik_property_mapping_provider_scope" "litellm_role" {
  name       = "LiteLLM Role"
  scope_name = "litellm_role"
  expression = <<-EOT
    return {"litellm_role": "proxy_admin"}
  EOT
}

resource "authentik_property_mapping_provider_scope" "sftpgo_username" {
  name       = "SFTGO Preferred Username"
  scope_name = "preferred_username"
  expression = <<-EOT
    return user.attributes.get("preferred_username", user.username)
  EOT
}
