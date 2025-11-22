Tofu init:
```bash
tofu init -upgrade -backend-config="../backend.tfvars"
```

Tofu plan:
```bash
tofu plan -var-file=."./op.tfvars"
```

### Directories

This Git repository contains the following directories under [Kubernetes](./kubernetes/).

```sh
📁 terraform
├── 📁 authentik
├── 📁 garage
├── 📁 uptimerobot
├── backend.tfvars (ignored)
├── op.tfvars (ignored)
```
