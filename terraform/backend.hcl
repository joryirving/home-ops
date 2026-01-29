# Backend Configuration for Terraform Modules
# This file can be referenced by individual modules for consistent backend setup

# S3-compatible backend configuration (Garage)
bucket         = "terraform-state"
region         = "ca-west-1"
endpoint       = "https://s3.jory.dev"
key_prefix     = "terraform/"
skip_tls_verify = false

# Authentication (should be provided via environment variables)
# access_key
# secret_key