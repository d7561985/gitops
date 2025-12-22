# syntax=docker/dockerfile:1
FROM python:3.11-slim

WORKDIR /app

# Install build dependencies for psutil and git for GitLab packages
RUN apt-get update && apt-get install -y gcc python3-dev git ca-certificates && rm -rf /var/lib/apt/lists/*

# Copy requirements first for better caching
COPY requirements.txt .

# Install dependencies with GitLab authentication
# In CI: docker build --secret id=gitlab_token,env=CI_JOB_TOKEN ...
# Locally: docker build --secret id=gitlab_token,src=$HOME/.gitlab_token ...
RUN --mount=type=secret,id=gitlab_token \
    GITLAB_TOKEN=$(cat /run/secrets/gitlab_token 2>/dev/null | tr -d '\n' || echo "") && \
    if [ -n "$GITLAB_TOKEN" ]; then \
        echo "machine gitlab.com login gitlab-ci-token password ${GITLAB_TOKEN}" > ~/.netrc && \
        chmod 600 ~/.netrc; \
    fi && \
    pip install --no-cache-dir -r requirements.txt && \
    rm -f ~/.netrc

# Copy application code
COPY . .

# Expose port
EXPOSE 8082

# Run the application
CMD ["python", "main.py"]
