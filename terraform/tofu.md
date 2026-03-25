## OpenTofu Configuration Guide

This repository contains OpenTofu configurations for managing infrastructure resources.

### File Organization

| File | Purpose |
|------|---------|
| `main.tofu` | Provider and resource configuration |
| `variables.tofu` | Input variable declarations |
| `outputs.tofu` | Output value declarations |
| `backend.tofu` | Backend configuration |
| `*.tofu` | Additional resources (buckets, flows, etc.) |

### Style Conventions

When modifying Terraform code, follow these conventions:

- **Indentation**: Use two spaces per nesting level
- **Naming**: Use lowercase with underscores (`resource_name`, not `resourceName`)
- **Resource names**: Use descriptive nouns, singular form (e.g., `aws_vpc.main` not `aws_vpc.vpcs`)
- **Variables**: Must include `type` and `description`
- **Outputs**: Must include `description`, mark sensitive values with `sensitive = true`
- **Version pinning**: Use `~>` for minor version flexibility (e.g., `~> 3.0`)

### Example Resource

```hcl
resource "garage_bucket" "data" {
  name = var.bucket_name
  tags = var.common_tags
}

variable "bucket_name" {
  description = "Name of the Garage S3 bucket"
  type       = string
}

output "bucket_id" {
  description = "ID of the created bucket"
  value       = garage_bucket.data.id
}
```

### Initialization

```bash
# Initialize OpenTofu with backend configuration
tofu init -upgrade -backend-config="../backend.tfvars"
```

### Planning

```bash
# Plan changes with variables file
tofu plan -var-file="./op.tfvars"
```

### Common Commands

```bash
# Apply changes
tofu apply -var-file="./op.tfvars"

# Destroy resources (use with caution)
tofu destroy -var-file="./op.tfvars"

# Import existing resources
tofu import -var-file="./op.tfvars" RESOURCE_TYPE.RESOURCE_NAME RESOURCE_ID

# View state
tofu state list

# Show outputs
tofu output
```

### Validation

Run before committing:

```bash
tofu fmt -recursive
tofu validate
```

### Directories

```
📁 terraform/
├── 📁 authentik/         # Identity management configuration
├── 📁 garage/            # S3-compatible storage configuration
├── 📁 uptimerobot/       # Monitoring service configuration
├── backend.tfvars        # Backend configuration (ignored)
└── op.tfvars             # Variables file (ignored)
```

### Best Practices

1. **Always plan before applying**: Run `tofu plan` to preview changes
2. **Use version control**: Track all `.tofu` files in Git
3. **Secure variable files**: Keep sensitive data in `.tfvars` files which are gitignored
4. **State management**: Ensure backend is properly configured for remote state
5. **Lock files**: Commit `tofu.lock.hcl` to ensure consistent provider versions
6. **Never commit**: `.terraform/`, `terraform.tfstate*`, `*.tfvars`, `*.tfplan`

### Troubleshooting

- If encountering lock issues: `rm .terraform.lock.hcl` then reinitialize
- For backend reconfiguration: `tofu init -reconfigure`
- To force unlock state (if locked): `tofu force-unlock <lock-ID>` (use cautiously)

---
