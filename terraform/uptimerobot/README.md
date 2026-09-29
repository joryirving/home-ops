# UptimeRobot

Manages [UptimeRobot](https://uptimerobot.com/) monitoring configuration.

## Resources

- Monitors
- Integrations (alert contacts)

## Notes

Requires 1Password Connect credentials in `op.tfvars` for API key retrieval.

Applied by tofu-controller on the utility cluster (`kubernetes/apps/utility/flux-system/terraform/uptimerobot.yaml`) after merge to `main`; see [`../tofu.md`](../tofu.md#how-changes-are-applied).
