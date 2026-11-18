# Project Maya on ganyu

The Maya service starts at one replica. The preparation Job stays suspended.
The Job uses a new
120 GiB PVC. It does not use the Strata PVC. Strata stays at zero replicas.
The Maya service uses the published v1.1.66 image digest. The v1.1.67
image is not available because its build failed. The service uses the
published v1.1.66 image digest until the v1.1.67 build is available.
The preparation Job downloads the three Maya-S24 shards at a pinned model
revision, checks their SHA-256 hashes, and builds the Maya pack before the
server starts.

## Prepare the model

1. Merge and reconcile the deployment change. Maya starts with one replica.
2. Check that Strata has zero replicas and that its PVC is still present.
3. Before merge, measure free system memory on ganyu. Do not merge if Maya's
   108 GiB memory request leaves too little headroom for node services.
4. In a reviewed Git change, set `project-maya-ganyu-prepare.spec.suspend` to
   `false`. Reconcile LiteLLM and wait for the Job to complete successfully.
5. Check the Job logs for `Maya-S24 shards verified; pack ready`. Check that
   the three shards and all pack files exist on `project-maya-ganyu-data`.

The initial merge starts Maya at one replica. The route changes place Maya in
the `glm-5.3-flash` alias and implementation pool. Strata stays stopped.

The Job does not start the Maya server. If preparation fails, the server will
not start and the pod will restart. Inspect the Job logs. The script verifies
existing shards and
re-downloads a shard if its hash does not match.

## Start Maya

1. Confirm Strata has zero replicas and its pod has stopped.
2. Wait for Maya to finish preparation, load the model, and pass its readiness
   probe. Send benchmark traffic only after readiness passes.
3. Keep Strata at zero replicas for the full Maya test. Do not delete either
   model PVC.

## Roll back to Strata

1. In a reviewed Git change, set Maya's replicas to `0`.
2. Restore the Strata LiteLLM implementation-pool rung and remove the Maya
   rung. Reconcile LiteLLM and wait for Maya's pod to stop.
3. Confirm that the NVIDIA GPU is free. Then set Strata's replicas to `1` in a
   reviewed Git change and reconcile LiteLLM again.
4. Keep `project-maya-ganyu-data` and `llmkube-ganyu-cache`. The first PVC holds
   Maya's prepared files. The second holds Strata's existing data.
