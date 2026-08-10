# foreman-dispatch-bridge

CronJob (`*/15`) that connects Dispatch (assignment) to LLMKube Foreman (execution):
retries failed Workloads, claims `status/ready` issues per lane, materializes `Workload`
CRs, and drains the pr-fix queue. All configuration is env on the HelmRelease here.

> **The loop this drives — dataflow, lanes, gate profiles, pr-fix, failure semantics, and
> the full env reference — is documented in
> [docs/src/notes/coding-loop.md](../../../../../../docs/src/notes/coding-loop.md).**
> Read that before changing `LANE_CODER_AGENTS`, `GATEPROFILE_MAP`, or `MAX_IN_PROGRESS`.
