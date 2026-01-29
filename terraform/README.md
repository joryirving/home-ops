# Terraform Infrastructure

This directory contains Terraform (OpenTofu) configurations for managing infrastructure resources.

## Modules

- [`authentik/`](./authentik/) — Authentik identity management
- [`garage/`](./garage/) — Garage S3-compatible storage
- [`uptimerobot/`](./uptimerobot/) — UptimeRobot monitoring

## Prerequisites

- [OpenTofu](https://opentofu.org/) >= 1.6.0
- 1Password CLI with Connect integration
- Properly configured backend (S3-compatible, e.g., Garage)

## Usage

```bash
tofu init -upgrade -backend-config="access_key=YOUR_ACCESS_KEY" -backend-config="secret_key=YOUR_SECRET_KEY"
tofu plan -var="OP_CONNECT_HOST=your-connect-url" -var="OP_CONNECT_TOKEN=your-connect-token"
tofu apply
```

## Backend

Shared backend configuration is in [`backend.hcl`](./backend.hcl).