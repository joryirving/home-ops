# Authentik

Manages Authentik identity provider configuration for single sign-on (SSO).

## Resources

- Applications
- Brands
- Directories
- Flows and stages
- Mappings and scopes
- Policies (password complexity, expression)
- System settings

## Notes

Requires 1Password Connect credentials in `op.tfvars` for secret retrieval.

Applied by tofu-controller on the utility cluster (`kubernetes/apps/utility/flux-system/terraform/authentik.yaml`) after merge to `main`; see [`../tofu.md`](../tofu.md#how-changes-are-applied).
