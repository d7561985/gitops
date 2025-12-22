# Sentry Demo - Project Guidelines

## Architecture Principles

This project follows these principles (in order of priority):

1. **KISS** - Keep It Simple, Stupid
2. **YAGNI** - You Aren't Gonna Need It
3. **DRY** - Don't Repeat Yourself
4. **SOLID** - Single responsibility, Open-closed, Liskov substitution, Interface segregation, Dependency inversion
5. **Clean Architecture** - Separation of concerns with clear boundaries

## Critical Requirements

### Code Generation from Proto Packages

**THIS IS CRITICAL!** All services MUST use generated code from proto packages:

```
gitlab.com/gitops-poc-dzha/api/gen/{service-name}/{language}.git
```

- **Never** write gRPC stubs manually
- **Always** use the generated packages from GitLab
- Proto packages are generated via CI from `api/proto/` definitions

### Protocol Support

Services must support protocol switching between:
- **Connect Protocol** (preferred) - Modern, HTTP-native
- **gRPC-Web** - Legacy fallback

Implementation should allow switching protocols without code changes.

## Docker Build Authentication

### Unified Approach: `.netrc`

All Dockerfiles use `.netrc` for GitLab authentication. This is the **only** approved method.

```dockerfile
RUN --mount=type=secret,id=gitlab_token \
    GITLAB_TOKEN=$(cat /run/secrets/gitlab_token 2>/dev/null | tr -d '\n' || echo "") && \
    if [ -n "$GITLAB_TOKEN" ]; then \
        echo "machine gitlab.com login gitlab-ci-token password ${GITLAB_TOKEN}" > ~/.netrc && \
        chmod 600 ~/.netrc; \
    fi && \
    <package-manager-install-command> && \
    rm -f ~/.netrc
```

**Why `.netrc`?**
- Standard mechanism (RFC 4616)
- Works universally: git, npm, pip, composer, curl
- No package-manager-specific hacks needed
- Secure: removed after install, not baked into image

### Language-Specific Notes

| Language | Package Manager | Special Configuration |
|----------|-----------------|----------------------|
| Node.js | npm | Works with `.netrc` directly |
| Python | pip | Works with `.netrc` directly |
| PHP | composer | Requires `type: "git"` (not `vcs`) + `gitlab-protocol: https` |

**PHP/Composer specifics:**
```json
{
  "repositories": [{ "type": "git", "url": "https://..." }],
  "config": { "gitlab-protocol": "https" }
}
```
Using `vcs` type causes Composer to auto-switch to SSH for private GitLab repos.

**Build commands:**
```bash
# Local build
echo -n "$GITLAB_TOKEN" > /tmp/gitlab_token
docker build --secret id=gitlab_token,src=/tmp/gitlab_token -t service:latest .

# CI build (in .gitlab-ci.yml)
echo "$CI_PUSH_TOKEN" > /tmp/gitlab_token
docker build --secret id=gitlab_token,src=/tmp/gitlab_token ...
```

See `docs/DOCKER_AUTH.md` for detailed documentation.

## Service Structure

```
services/sentry-demo/
├── frontend/          # Angular + Connect-Web
├── game-engine/       # Python + Tornado + Connect
├── payment-service/   # Node.js + Express + Connect
├── wager-service/     # PHP + Symfony + gRPC
└── .gitlab-ci.yml     # Unified CI with templates
```

## CI/CD

### Templates

- `.build-template` - Base Docker build template
- `.build-with-proto-template` - Extends base, adds BuildKit secrets for proto packages
- `.release-template` - ArgoCD deployment wait

### Adding New Service

1. Create Dockerfile with `.netrc` authentication pattern
2. Add job to `.gitlab-ci.yml`:
   ```yaml
   build:new-service:
     extends: .build-with-proto-template
     variables:
       SERVICE_NAME: new-service
       SERVICE_PATH: new-service
       IMAGE_TAG_ALIAS: latest
     rules:
       - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
         changes:
           - new-service/**/*
   ```

## Libraries & Dependencies

- Keep libraries up to date
- Prefer well-maintained, popular packages
- Check compatibility before upgrading

## Code Style

- No excessive comments or docstrings for obvious code
- Self-documenting code preferred
- Comments only for non-obvious business logic
