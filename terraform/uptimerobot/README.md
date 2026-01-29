# UptimeRobot Terraform Module

This module manages UptimeRobot monitoring resources using the UptimeRobot Terraform provider.

## Resources Managed

- UptimeRobot Monitors
- UptimeRobot Integrations
- UptimeRobot Alert Contacts

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| OP\_CONNECT\_HOST | 1Password Connect URL | `string` | n/a | yes |
| OP\_CONNECT\_TOKEN | 1Password Connect token | `string` | n/a | yes |

## Outputs

No outputs defined.

## Backend Configuration

This module expects a remote backend configuration to be provided via the `backend.tofu` file.

## Usage

```hcl
module "uptimerobot" {
  source            = "./uptimerobot"
  OP_CONNECT_HOST   = var.op_connect_host
  OP_CONNECT_TOKEN  = var.op_connect_token
}
```