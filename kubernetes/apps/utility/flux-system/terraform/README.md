# OpenTofu Controller Configuration

This directory contains FluxCD Terraform controller configurations for managing infrastructure resources.

## Services Managed

- **Authentik**: Identity management
- **Garage**: S3-compatible object storage
- **UptimeRobot**: Monitoring service configurations

## Architecture

The setup uses:
- FluxCD Terraform controller to run OpenTofu in-cluster
- S3-compatible backend (s3.jory.dev) for state management
- OCI repository for source code distribution
- Kubernetes secrets for sensitive variables

## Adding New Services

To add a new service:

1. Create a new Terraform configuration in your source repository
2. Add a new Terraform CRD file in this directory
3. Update the kustomization.yaml to include the new resource
4. Create necessary secrets for the service

## Best Practices Implemented

- Resource limits to prevent excessive consumption
- Retry logic for transient failures
- Proper timeout configurations
- Consistent naming and labeling

## Troubleshooting

Common issues and solutions:

1. **Plan approval failures**: Check if approvePlan: auto is appropriate for your security requirements
2. **Backend connection issues**: Verify S3 endpoint accessibility and credentials
3. **Resource limits**: Adjust runnerPodTemplate resources based on your Terraform complexity

## Additional Recommendations

### Resource Management
Consider adding resource limits to prevent excessive consumption by the OpenTofu controller:

```yaml
spec:
  runnerPodTemplate:
    spec:
      resources:
        limits:
          cpu: "1000m"
          memory: "1Gi"
        requests:
          cpu: "100m"
          memory: "128Mi"
```

### Health Checks
Add health assessments to monitor the state of managed resources:

```yaml
spec:
  healthChecks:
  - name: terraform-controller-health
    type: read
    check:
      target: kubernetes_secret_v1.state_backend
```

### Consistent Naming
Ensure all Terraform CRDs follow a consistent naming pattern (using "terraform-" prefix consistently).

---

*This documentation has been enhanced by [Miso](https://openclaw.ai), an AI assistant.*
