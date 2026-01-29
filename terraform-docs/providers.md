# Terraform Providers

This document lists the Terraform providers used in this repository and their purposes.

## Core Providers

### authentik
- **Source**: `goauthentik/authentik`
- **Purpose**: Manage Authentik identity management resources
- **Version**: `2025.12.0`
- **Configuration**: Uses API token from 1Password

### aws
- **Source**: `hashicorp/aws`
- **Purpose**: Manage S3-compatible storage resources (Garage)
- **Configuration**: Uses AWS-compatible credentials for Garage

### uptimerobot
- **Source**: `louy/uptimerobot`
- **Purpose**: Manage UptimeRobot monitoring resources
- **Configuration**: Uses API key from 1Password

### onepassword
- **Source**: `1password/onepassword`
- **Purpose**: Retrieve secrets from 1Password Connect
- **Version**: `3.1.2`
- **Configuration**: Uses Connect URL and token

## Provider Configuration

All providers are configured to retrieve secrets from 1Password Connect to maintain security best practices. Provider configurations are typically located in the `main.tofu` file of each module.

## Version Management

Provider versions are pinned to specific versions to ensure consistency across environments. Regular updates should be performed to take advantage of new features and security fixes.