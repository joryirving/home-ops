# Terraform Best Practices

- Use descriptive resource names: `resource_type_component_purpose`
- Store secrets via 1Password Connect (`OP_CONNECT_HOST`, `OP_CONNECT_TOKEN`)
- Pin provider versions explicitly
- Never hardcode credentials
- Use remote backend with state locking