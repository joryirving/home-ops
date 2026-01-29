# Provider Management

This document describes how providers are managed across the Terraform modules in this repository.

## Common Providers

The following providers are used across multiple modules:

### 1Password Provider
- **Source**: `1password/onepassword`
- **Version**: `3.1.2`
- **Purpose**: Retrieving secrets from 1Password Connect
- **Modules**: authentik, garage, uptimerobot

## Module-Specific Providers

### Authentik Module
- **authentik**: `goauthentik/authentik` version `2025.12.0`
- **Purpose**: Managing Authentik identity management resources

### Garage Module
- **garage**: `schwitzd/garage` version `1.2.2`
- **Purpose**: Managing Garage S3-compatible storage resources

### UptimeRobot Module
- **uptimerobot**: `uptimerobot/uptimerobot` version `1.3.9`
- **Purpose**: Managing UptimeRobot monitoring resources

## Provider Version Management

Provider versions are explicitly pinned in each module to ensure consistency and reproducible deployments. When updating provider versions:

1. Test changes in a non-production environment
2. Review provider changelogs for breaking changes
3. Update versions in all relevant modules simultaneously
4. Document any migration steps in this file

## Provider Configuration

All providers are configured to use secrets from 1Password Connect to maintain security best practices. Provider configuration files should not contain hardcoded credentials.