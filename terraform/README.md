# Terraform Infrastructure

This directory contains Terraform configurations for managing infrastructure resources.

## Modules

- [authentik](./authentik/) - Authentik identity management resources
- [garage](./garage/) - Garage S3-compatible storage resources  
- [uptimerobot](./uptimerobot/) - UptimeRobot monitoring resources

## Documentation

Comprehensive documentation for Terraform best practices and patterns can be found in the [documentation repository](../terraform-docs/).

## Prerequisites

- [OpenTofu](https://opentofu.org/) >= 1.6.0
- 1Password CLI with Connect integration
- Properly configured backend storage

## Usage

### Initialize Terraform

```bash
tofu init -upgrade -backend-config="access_key=YOUR_ACCESS_KEY" -backend-config="secret_key=YOUR_SECRET_KEY"
```

### Plan Changes

```bash
tofu plan -var="OP_CONNECT_HOST=your-connect-url" -var="OP_CONNECT_TOKEN=your-connect-token"
```

### Apply Changes

```bash
tofu apply -var="OP_CONNECT_HOST=your-connect-url" -var="OP_CONNECT_TOKEN=your-connect-token"
```

## Backend Configuration

The backend is configured to use S3-compatible storage (Garage) with state locking. Backend credentials are provided via variables or environment variables.