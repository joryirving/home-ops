# Project Maya on ganyu

The Maya service and its preparation Job start disabled. The Job uses a new
120 GiB PVC. It does not use the Strata PVC. Strata stays at zero replicas.
The Maya service uses the published v1.1.66 image digest. The v1.1.67
image is not available because its build failed.
The preparation Job downloads the three Maya-S24 shards at a pinned model
revision, checks their SHA-256 hashes, and builds the Maya pack. Maya stays at
zero replicas until a separate approved change starts it.

## Prepare the model

1. Merge and reconcile the deployment change. Maya remains stopped.
2. Check that Strata has zero replicas and that its PVC is still present.
3. Measure free system memory on ganyu. Stop if the node does not have enough
   headroom for Maya's 108 GiB memory request and the existing system load.
4. In a reviewed Git change, set `project-maya-ganyu-prepare.spec.suspend` to
   `false`. Reconcile LiteLLM and wait for the Job to complete successfully.
5. Check the Job logs for `Maya-S24 shards verified; pack ready`. Check that
   the three shards and all pack files exist on `project-maya-ganyu-data`.

The Job does not start the Maya server. If preparation fails, keep Maya at zero
replicas and inspect the Job logs. The script verifies existing shards and
re-downloads a shard if its hash does not match.

## Start Maya

1. Confirm Strata has zero replicas and its pod has stopped.
2. Measure free system memory on ganyu again. Stop if Maya's request would
   leave too little memory for the node and its services.
3. In a reviewed Git change, set Maya's `InferenceService.spec.replicas` to
   `1`. Keep the preparation Job unsuspended so Flux does not rerun it.
4. In that change, promote the isolated `glm-5.3-flash-maya` model to order 1.
   Add it to the shared `glm-5.3-flash` alias and implementation pool only
   after Maya is ready.
5. Reconcile LiteLLM. Wait for Maya's readiness probe to pass before sending
   benchmark traffic.
6. Keep Strata at zero replicas for the full Maya test. Do not delete either
   model PVC.

## Roll back to Strata

1. In a reviewed Git change, set Maya's replicas to `0`.
2. Reconcile LiteLLM and wait for Maya's pod to stop.
3. Confirm that the NVIDIA GPU is free. Then set Strata's replicas to `1` in a
   reviewed Git change and reconcile LiteLLM again.
4. Keep `project-maya-ganyu-data` and `llmkube-ganyu-cache`. The first PVC holds
   Maya's prepared files. The second holds Strata's existing data.
