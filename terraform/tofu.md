## OpenTofu Configuration Guide

This repository contains OpenTofu configurations for managing infrastructure resources.

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

### Directories

This repository contains the following OpenTofu configurations:

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
2. **Use version control**: Track all `.tf` files in Git
3. **Secure variable files**: Keep sensitive data in `.tfvars` files which are gitignored
4. **State management**: Ensure backend is properly configured for remote state
5. **Lock files**: Commit `tofu.lock.hcl` to ensure consistent provider versions

### Troubleshooting

- If encountering lock issues: `rm .terraform.lock.hcl` then reinitialize
- For backend reconfiguration: `tofu init -reconfigure`
- To force unlock state (if locked): `tofu force-unlock <lock-ID>` (use cautiously)

---
