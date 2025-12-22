# syntax=docker/dockerfile:1
FROM node:20-alpine

WORKDIR /app

# Install dependencies for native modules and git for GitLab packages
RUN apk add --no-cache python3 make g++ git

# Copy package files
COPY package.json ./

# Install dependencies with GitLab authentication
# In CI: docker build --secret id=gitlab_token,env=CI_JOB_TOKEN ...
# Locally: docker build --secret id=gitlab_token,src=$HOME/.gitlab_token ...
RUN --mount=type=secret,id=gitlab_token \
    GITLAB_TOKEN=$(cat /run/secrets/gitlab_token 2>/dev/null | tr -d '\n' || echo "") && \
    if [ -n "$GITLAB_TOKEN" ]; then \
        echo "machine gitlab.com login gitlab-ci-token password ${GITLAB_TOKEN}" > ~/.netrc && \
        chmod 600 ~/.netrc; \
    fi && \
    npm install --omit=dev && \
    rm -f ~/.netrc

# Copy application code
COPY . .

# Expose port
EXPOSE 8083

# Run the application
CMD ["node", "src/index.js"]
