# Authentik Terraform Module

This module manages Authentik resources using the Authentik Terraform provider.

## Resources Managed

- Authentik Applications
- Authentik Flows
- Authentik Stages
- Authentik Mappings
- Authentik Scopes
- Authentik Directory settings
- Authentik Customization settings
- Authentik System settings

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| OP\_CONNECT\_HOST | 1Password Connect URL | `string` | n/a | yes |
| OP\_CONNECT\_TOKEN | 1Password Connect token | `string` | n/a | yes |
| CLUSTER\_DOMAIN | Domain for Authentik | `string` | `"jory.dev"` | no |

## Outputs

No outputs defined.

## Backend Configuration

This module expects a remote backend configuration to be provided via the `backend.tofu` file.

## Usage

```hcl
module "authentik" {
  source            = "./authentik"
  OP_CONNECT_HOST   = var.op_connect_host
  OP_CONNECT_TOKEN  = var.op_connect_token
  CLUSTER_DOMAIN    = var.cluster_domain
}
```