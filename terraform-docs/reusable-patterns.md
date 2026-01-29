# Reusable Terraform Patterns

This document describes common patterns used across the Terraform modules in this repository.

## 1Password Integration Pattern

All modules follow a consistent pattern for retrieving secrets from 1Password:

```hcl
provider "onepassword" {
  connect_url   = var.OP_CONNECT_HOST
  connect_token = var.OP_CONNECT_TOKEN
}

data "onepassword_vault" "kubernetes" {
  name = "Kubernetes"
}

module "onepassword_<service>" {
  source = "github.com/joryirving/terraform-1password-item"
  vault  = data.onepassword_vault.kubernetes.name
  item   = "<service_name>"
}
```

## Backend Configuration Pattern

All modules use a consistent S3-compatible backend configuration:

```hcl
terraform {
  backend "s3" {
    bucket = "terraform-state"
    key    = "<module_name>/<module_name>.tfstate"
    region = "ca-west-1"

    endpoints = {
      s3 = "https://s3.jory.dev"
    }

    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    use_path_style              = true
  }
}
```

## Provider Declaration Pattern

All modules declare providers with version constraints and configure them to use 1Password for secrets:

```hcl
terraform {
  required_providers {
    <provider_name> = {
      source  = "<provider_source>"
      version = "<version_constraint>"
    }

    onepassword = {
      source  = "1password/onepassword"
      version = "3.1.2"
    }
  }
}
```

## Module Structure

Each module follows a consistent file structure:

- `main.tofu` - Provider declarations and required providers
- `variables.tofu` - Input variables with descriptions
- `outputs.tofu` - Output values (if applicable)
- `backend.tofu` - Backend configuration
- Other files grouped by resource type or functionality

## Secret Management Pattern

All sensitive values are retrieved from 1Password and never hardcoded in the configuration files. The pattern ensures secrets are handled securely while maintaining configuration flexibility.