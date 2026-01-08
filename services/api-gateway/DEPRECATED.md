# DEPRECATED

This directory is deprecated. The API Gateway has been split into two repositories:

## New Structure

1. **api-gateway-image** - Golden image (Envoy + config generator)
   - Location: `services/api-gateway-image/`
   - Contains: Source code, Dockerfile
   - Changes: Rarely (infrastructure changes)

2. **api-gw** - Config repository (config.yaml + deployment)
   - Location: `services/api-gw/`
   - Contains: config.yaml, .cicd/, Dockerfile (micro-image)
   - Changes: Frequently (routes, clusters, auth policies)

## Migration

After creating GitLab repositories and pushing the new structure, delete this directory:

```bash
rm -rf services/api-gateway
```
