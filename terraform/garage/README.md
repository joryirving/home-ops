# Garage

Manages [Garage](https://garagehq.deuxfleurs.nl/) - S3-compatible object storage (self-hosted Cloudflare R2 alternative).

## Resources

- S3 buckets (`buckets.tofu`, module `modules/garage`)
- Per-bucket access keys, written back to 1Password as `<bucket>-bucket` items (module `modules/create-secret`)
- Admin key, written to 1Password as `garage-admin`

## Notes

Requires 1Password Connect credentials in `op.tfvars` for secret retrieval.

Applied by tofu-controller on the utility cluster (`kubernetes/apps/utility/flux-system/terraform/garage.yaml`) after merge to `main`; see [`../tofu.md`](../tofu.md#how-changes-are-applied).
