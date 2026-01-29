# Terraform Best Practices

This document outlines the best practices for managing Terraform configurations in this repository.

## Naming Conventions

- Use descriptive names for resources that follow the pattern: `resource_type_component_purpose`
- Use lowercase with underscores as separators
- Include the component or service name in the resource name

## File Organization

- Store Terraform configurations in module-specific directories
- Use `.tofu` extensions for Terraform files (following OpenTofu convention)
- Keep related resources in the same file when they are tightly coupled
- Split large configurations into multiple files by resource type or functionality

## Variables

- Always include descriptions for variables
- Mark sensitive variables with `sensitive = true`
- Use appropriate default values when possible
- Group related variables together in `variables.tofu`

## Backend Configuration

- Use remote backend for all production configurations
- Enable state locking to prevent conflicts
- Use consistent naming for state files
- Store backend credentials securely (preferably via environment variables)

## Security

- Never hardcode sensitive information in Terraform files
- Use 1Password integration for secrets
- Regularly rotate access keys and tokens
- Limit permissions to the minimum required for each configuration

## Version Management

- Specify provider versions explicitly
- Use `.terraform-version` file to track expected version
- Regularly update providers to benefit from bug fixes and features
- Test changes in non-production environments first

## Documentation

- Maintain README.md files for each module
- Document variable purposes and valid values
- Include usage examples in module READMEs
- Keep outputs documented and meaningful