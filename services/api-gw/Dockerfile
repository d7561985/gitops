# =============================================================================
# API Gateway Micro Image
# =============================================================================
# Extends golden image with project-specific config.yaml
#
# This is the image that gets deployed. It combines:
#   - Base: api-gateway-image (Envoy + config generator)
#   - Config: config.yaml (routes, clusters, auth policies)
#
# Build is fast (~5 seconds) because only config.yaml is added.
# =============================================================================

ARG BASE_IMAGE=registry.gitlab.com/gitops-poc-dzha/services/api-gateway-image
ARG BASE_VERSION=latest

FROM ${BASE_IMAGE}:${BASE_VERSION}

# Add project-specific configuration
COPY config.yaml /opt/config-source/config.yaml
