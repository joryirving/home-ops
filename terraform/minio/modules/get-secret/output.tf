output "data" {
  sensitive = true

  value = merge(
    {
      access-key = data.bitwarden_item_login.item.username
      secret-key = data.bitwarden_item_login.item.password
    },

    merge([
      for field in data.bitwarden_item_login.item.field :
      {
        "${field.name}" = field.hidden != "" ? sensitive(field.hidden) : field.text
      }
    ]...)
  )
}
