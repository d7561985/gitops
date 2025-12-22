FROM node:20-slim AS builder

# Build arguments
ARG SENTRY_DSN
ARG API_URL
ARG APP_VERSION
ARG USE_CONNECT_PROTOCOL=true

# Install git and ca-certificates for npm git dependencies
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy package files first for better caching
COPY package*.json ./

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
    npm ci --prefer-offline --no-audit && \
    rm -f ~/.netrc

# Copy scripts directory for environment generation
COPY scripts ./scripts

# Copy source code
COPY . .

# Generate environment files with build arguments
ENV SENTRY_DSN=${SENTRY_DSN}
ENV API_URL=${API_URL}
ENV APP_VERSION=${APP_VERSION}
ENV USE_CONNECT_PROTOCOL=${USE_CONNECT_PROTOCOL}
RUN node scripts/generate-env.js

# Build the app
RUN npm run build

# Install Sentry CLI and inject debug-ids into built files
RUN npm install -g @sentry/cli
RUN npx @sentry/cli sourcemaps inject ./dist/frontend || echo "Debug ID injection skipped"

# Production stage
FROM nginx:alpine

# Copy built app
COPY --from=builder /app/dist/frontend /usr/share/nginx/html

# Copy nginx config
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Expose port
EXPOSE 4200

CMD ["nginx", "-g", "daemon off;"]