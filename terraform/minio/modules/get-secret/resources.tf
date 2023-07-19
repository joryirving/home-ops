output "data" {
  sensitive = true

  value = merge(
    {
      username = data.bitwarden_item_login.item.username
      password = data.bitwarden_item_login.item.password
    },

    merge([
      for field in data.bitwarden_item_login.item.field :
      {
        "${field.name}" = field.hidden != "" ? sensitive(field.hidden) : field.text
      }
    ]...)
  )
}
