locals {
  authentik_groups = {
    downloads      = { name = "Downloads" }
    games          = { name = "Games" }
    grafana_admins = { name = "Grafana Admins" }
    home           = { name = "Home" }
    infrastructure = { name = "Infrastructure" }
    media          = { name = "Media" }
    monitoring     = { name = "Monitoring" }
    users          = { name = "Users" }
  }
}

data "authentik_group" "admins" {
  name = "authentik Admins"
}

resource "authentik_group" "default" {
  for_each     = local.authentik_groups
  name         = each.value.name
  is_superuser = false
}

resource "authentik_policy_binding" "application_policy_binding" {
  for_each = local.applications

  target = authentik_application.application[each.key].uuid
  group  = authentik_group.default[each.value.group].id
  order  = 0
}

resource "authentik_user" "Jory" {
  username = "LilDrunkenSmurf"
  name     = "Jory Irving"
  email    = "jory@jory.dev"
  groups = concat(
    [data.authentik_group.admins.id],
    values(authentik_group.default)[*].id
  )
}
