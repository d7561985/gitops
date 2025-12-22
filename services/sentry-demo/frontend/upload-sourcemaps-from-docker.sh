#!/bin/bash

# Script to upload source maps from Docker container after build
# This ensures we upload the exact same files that are deployed

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Load environment variables from the script's directory
if [ -f "$SCRIPT_DIR/.env" ]; then
    export $(cat "$SCRIPT_DIR/.env" | grep -v '^#' | xargs)
fi

# Get current version from project root
if [ -f "$SCRIPT_DIR/../../.version" ]; then
    CURRENT_VERSION=$(cat "$SCRIPT_DIR/../../.version")
elif [ -f ".version" ]; then
    CURRENT_VERSION=$(cat .version)
else
    echo "❌ Error: .version file not found"
    exit 1
fi

echo "📦 Uploading source maps from Docker container..."
echo "   Version: $CURRENT_VERSION"
echo "   Container: sentry-poc-frontend"

# Check if container is running
if ! docker ps | grep -q sentry-poc-frontend; then
    echo "❌ Error: Frontend container is not running"
    echo "   Run ./start-prod.sh first"
    exit 1
fi

# Ensure we have auth token
if [ -z "$SENTRY_AUTH_TOKEN" ]; then
    echo "❌ Error: SENTRY_AUTH_TOKEN not set"
    echo "   Set it in $SCRIPT_DIR/.env file"
    exit 1
fi

# Ensure we have org and project
if [ -z "$SENTRY_ORG" ] || [ -z "$SENTRY_PROJECT" ]; then
    echo "❌ Error: SENTRY_ORG or SENTRY_PROJECT not set"
    echo "   Set them in $SCRIPT_DIR/.env file"
    echo "   Current values:"
    echo "   - SENTRY_ORG: $SENTRY_ORG"
    echo "   - SENTRY_PROJECT: $SENTRY_PROJECT"
    exit 1
fi

# Create a temporary directory
TEMP_DIR=$(mktemp -d)
echo "📁 Using temporary directory: $TEMP_DIR"

# Copy files from container
echo "📥 Copying files from container..."
docker cp sentry-poc-frontend:/usr/share/nginx/html/. $TEMP_DIR/

# Upload source maps with version
echo "📤 Uploading source maps to Sentry..."
cd $TEMP_DIR

npx @sentry/cli sourcemaps upload \
  --org "$SENTRY_ORG" \
  --project "$SENTRY_PROJECT" \
  --release "$CURRENT_VERSION" \
  .

# Clean up
cd - > /dev/null
rm -rf $TEMP_DIR

echo "✅ Source maps uploaded successfully from deployed container!"
echo "   Version: $CURRENT_VERSION"
echo "   Files were taken directly from the running container"