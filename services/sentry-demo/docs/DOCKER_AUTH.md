# Docker Build Authentication for Private GitLab Packages

## Overview

All services in this monorepo use generated proto packages from private GitLab repositories. This document describes the unified authentication approach using `.netrc`.

## The Problem

Services depend on proto packages hosted as private git repositories:

```
git+https://gitlab.com/gitops-poc-dzha/api/gen/game-engine/python.git
git+https://gitlab.com/gitops-poc-dzha/api/gen/payment-service/nodejs.git
git+https://gitlab.com/gitops-poc-dzha/api/gen/wager-service/php.git
```

During Docker build, package managers (npm, pip, composer) need to authenticate with GitLab to clone these repositories.

## Solution: `.netrc` with BuildKit Secrets

### Why `.netrc`?

| Approach | npm | pip | composer | git | Security |
|----------|-----|-----|----------|-----|----------|
| `.netrc` | ✅ | ✅ | ✅ | ✅ | ✅ Removed after install |
| `git config url.insteadOf` | ✅ | ✅ | ✅ | ✅ | ⚠️ Stored in git config |
| Package-specific tokens | ✅ | ❌ | ✅ | ❌ | ⚠️ Manager-specific |
| Build args | ✅ | ✅ | ✅ | ✅ | ❌ Baked into image layers |

`.netrc` is the most universal and secure approach:
- Standard mechanism defined in RFC 4616
- Supported by all tools that use HTTP authentication
- Can be safely removed after package installation
- Not stored in Docker image layers when using BuildKit secrets

### Dockerfile Pattern

```dockerfile
# syntax=docker/dockerfile:1

# ... base image and setup ...

# Install dependencies with GitLab authentication via .netrc
# .netrc is a standard mechanism that works with git, composer, npm, pip
# In CI: docker build --secret id=gitlab_token,env=CI_JOB_TOKEN ...
# Locally: docker build --secret id=gitlab_token,src=$HOME/.gitlab_token ...
RUN --mount=type=secret,id=gitlab_token \
    GITLAB_TOKEN=$(cat /run/secrets/gitlab_token 2>/dev/null | tr -d '\n' || echo "") && \
    if [ -n "$GITLAB_TOKEN" ]; then \
        echo "machine gitlab.com login gitlab-ci-token password ${GITLAB_TOKEN}" > ~/.netrc && \
        chmod 600 ~/.netrc; \
    fi && \
    <PACKAGE_INSTALL_COMMAND> && \
    rm -f ~/.netrc
```

Replace `<PACKAGE_INSTALL_COMMAND>` with:
- **npm**: `npm ci --prefer-offline --no-audit` or `npm install --omit=dev`
- **pip**: `pip install --no-cache-dir -r requirements.txt`
- **composer**: `composer install --no-scripts --no-dev`

### Build Commands

#### Local Development

```bash
# Store your GitLab Personal Access Token
echo -n "glpat-xxxxxxxxxxxx" > /tmp/gitlab_token

# Build with BuildKit secret
docker build --secret id=gitlab_token,src=/tmp/gitlab_token -t myservice:latest .

# Or use environment variable
export GITLAB_TOKEN="glpat-xxxxxxxxxxxx"
echo -n "$GITLAB_TOKEN" > /tmp/gitlab_token
docker build --secret id=gitlab_token,src=/tmp/gitlab_token -t myservice:latest .

# Cleanup
rm /tmp/gitlab_token
```

#### GitLab CI

The `.gitlab-ci.yml` uses the `.build-with-proto-template`:

```yaml
build:myservice:
  extends: .build-with-proto-template
  variables:
    SERVICE_NAME: myservice
    SERVICE_PATH: myservice
    IMAGE_TAG_ALIAS: latest
```

The template handles:
1. Writing `CI_PUSH_TOKEN` to temporary file
2. Passing it as BuildKit secret
3. Cleaning up after build

### Token Requirements

| Environment | Token Type | Variable | Scope |
|-------------|------------|----------|-------|
| Local | Personal Access Token | `GITLAB_TOKEN` | `read_repository` |
| GitLab CI | Group Access Token | `CI_PUSH_TOKEN` | `read_repository`, `write_repository` |

Note: `CI_JOB_TOKEN` doesn't have cross-project access, so we use `CI_PUSH_TOKEN` (Group Access Token).

## Troubleshooting

### "Repository not found"

1. Check the package URL in your dependency file
2. Verify the repository exists in GitLab
3. Ensure token has `read_repository` scope

### "Authentication required"

1. Verify token is correctly passed to Docker build
2. Check token hasn't expired
3. Ensure `.netrc` is created before package install command

### Build works locally but fails in CI

1. Verify `CI_PUSH_TOKEN` is set in GitLab CI/CD variables
2. Check token has access to the `api/gen/*` repositories
3. Ensure `DOCKER_BUILDKIT: "1"` is set in job variables

## Security Considerations

1. **Never** use `ARG` or `ENV` for tokens - they're stored in image layers
2. **Always** use BuildKit secrets (`--mount=type=secret`)
3. **Always** remove `.netrc` after package installation
4. **Never** commit tokens to git (add to `.gitignore`)
5. Use short-lived tokens where possible

## Version Compatibility

### Python (PEP 440)

Python packages require PEP 440 compliant versions. Use `+` for local versions:

```
version = "0.0.0+abc123"  # Correct
version = "0.0.0-abc123"  # Wrong - will fail pip install
```

### Node.js

Git dependencies in package.json:

```json
{
  "dependencies": {
    "@scope/package": "git+https://gitlab.com/group/repo.git#main"
  }
}
```

### PHP/Composer

**Important**: Use `type: "git"` instead of `type: "vcs"` to prevent Composer from auto-switching to SSH protocol.

```json
{
  "repositories": [
    {
      "type": "git",
      "url": "https://gitlab.com/group/repo.git"
    }
  ],
  "config": {
    "gitlab-protocol": "https"
  }
}
```

Why `git` instead of `vcs`:
- `vcs` triggers Composer's VCS driver which may switch to SSH for private GitLab repos
- `git` forces direct git clone with the specified URL
- See [Composer issue #11808](https://github.com/composer/composer/issues/11808)

**Note**: This configuration is in the **consuming service's** `composer.json`, not in the proto package itself. The proto packages generated by `api/ci/templates/proto-gen/template.yml` are correct.
