# Garage Terraform Module

This module manages Garage S3-compatible storage resources using the AWS Terraform provider.

## Resources Managed

- S3 Buckets
- S3 Bucket Policies
- IAM Users
- IAM Access Keys
- IAM Policy Attachments

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| OP\_CONNECT\_HOST | 1Password Connect URL | `string` | n/a | yes |
| OP\_CONNECT\_TOKEN | 1Password Connect token | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| buckets | Created bucket details |

## Backend Configuration

This module expects a remote backend configuration to be provided via the `backend.tofu` file.

## Usage

```hcl
module "garage" {
  source            = "./garage"
  OP_CONNECT_HOST   = var.op_connect_host
  OP_CONNECT_TOKEN  = var.op_connect_token
}
```