Tofu init:
```bash
tofu init -upgrade -backend-config="../backend.tfvars"
```

Tofu plan:
```bash
tofu plan -var-file=."./op.tfvars"
```
