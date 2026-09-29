## OpenTofu Configuration Guide

This repository contains OpenTofu configurations for managing infrastructure resources.

### File Organization

| File             | Purpose                                      |
| ---------------- | -------------------------------------------- |
| `main.tofu`      | Provider and resource configuration          |
| `variables.tofu` | Input variable declarations                  |
| `outputs.tofu`   | Output value declarations (where applicable) |
| `backend.tofu`   | Backend configuration                        |
| `*.tofu`         | Additional resources (buckets, flows, etc.)  |

### Style Conventions

When modifying Terraform code, follow these conventions:

- **Indentation**: Use two spaces per nesting level
- **Naming**: Use lowercase with underscores (`resource_name`, not `resourceName`)
- **Resource names**: Use descriptive nouns, singular form (e.g., `aws_vpc.main` not `aws_vpc.vpcs`)
- **Variables**: Must include `type` and `description`
- **Outputs**: Must include `description`, mark sensitive values with `sensitive = true`
- **Version pinning**: Pin providers to exact versions (e.g., `version = "3.3.1"`); Renovate bumps them

### Example Resource

From `garage/modules/garage/`:

```hcl
resource "garage_bucket" "bucket" {
  global_alias = var.bucket_name
}

resource "garage_key" "access_key" {
  name = "${var.bucket_name}-key"
}

resource "garage_bucket_key" "bucket_key" {
  access_key_id = garage_key.access_key.id
  bucket_id     = garage_bucket.bucket.id
  owner         = true
  read          = true
  write         = true
}
```

### How changes are applied

1. **PR**: the `Terraform Diff` workflow (`.github/workflows/terraform-diff.yaml`) runs `tofu fmt -check`, `tofu init`, `tofu validate` and `tofu plan` for each changed module on the utility runner and posts the plan as a PR comment.
2. **Merge**: the `Publish Terraform` workflow (`.github/workflows/terraform-publish.yaml`) pushes `terraform/` as an OCI artifact to `ghcr.io/joryirving/manifests/terraform`, tagged `main`.
3. **Apply**: tofu-controller on the utility cluster reconciles the `Terraform` resources in `kubernetes/apps/utility/flux-system/terraform/` (one per module) from that artifact (polled every 1m) with `approvePlan: auto` and `interval: 12h`.

The commands below are for local runs and assume a local `backend.tfvars` and `op.tfvars`.

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
│   └── 📁 modules/       # garage (bucket + key) and create-secret (1Password item)
├── 📁 uptimerobot/       # Monitoring service configuration
├── backend.tfvars        # Backend configuration (ignored)
└── op.tfvars             # Variables file (ignored)
```

### Best Practices

1. **Always plan before applying**: Run `tofu plan` to preview changes
2. **Use version control**: Track all `.tofu` files in Git
3. **Secure variable files**: Keep sensitive data in `.tfvars` files which are gitignored
4. **State management**: Ensure backend is properly configured for remote state
5. **Lock files**: `.terraform.lock.hcl` is gitignored; exact provider pins in `main.tofu` keep versions consistent
6. **Never commit**: `.terraform/`, `.terraform.lock.hcl`, `terraform.tfstate*`, `*.tfvars`, `*.tfplan`

### Troubleshooting

- If encountering lock issues: `rm .terraform.lock.hcl` then reinitialize
- For backend reconfiguration: `tofu init -reconfigure`
- To force unlock state (if locked): `tofu force-unlock <lock-ID>` (use cautiously)

---
