# Reusable Patterns

## 1Password Integration
```hcl
provider "onepassword" {
  connect_url   = var.OP_CONNECT_HOST
  connect_token = var.OP_CONNECT_TOKEN
}
```

## Backend Configuration
```hcl
terraform {
  backend "s3" {
    bucket = "terraform-state"
    key    = "module/module.tfstate"
    region = "ca-west-1"
    endpoints = { s3 = "https://s3.jory.dev" }
    skip_credentials_validation = true
    use_path_style = true
  }
}
```