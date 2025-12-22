#!/bin/bash

# Script for uploading source maps to Sentry with debug-ids support
# Compatible with Sentry SDK v9 and debug-ids

# Load environment variables from .env file in frontend directory
if [ -f .env ]; then
    echo "📋 Loading environment variables from frontend/.env..."
    export $(cat .env | grep -v '^#' | xargs)
fi

SENTRY_ORG=${SENTRY_ORG:-"your-org"}
SENTRY_PROJECT=${SENTRY_PROJECT:-"igaming-frontend"}
SENTRY_URL=${SENTRY_URL:-"https://sentry.io"}

echo "📦 Uploading source maps to Sentry with debug-ids..."
echo "   URL: $SENTRY_URL"
echo "   Org: $SENTRY_ORG"
echo "   Project: $SENTRY_PROJECT"

# Ensure we have auth token
if [ -z "$SENTRY_AUTH_TOKEN" ]; then
  echo "❌ Error: SENTRY_AUTH_TOKEN not set"
  echo "Get your token from: https://sentry.io/settings/account/api/auth-tokens/"
  exit 1
fi

# Inject debug-ids into the built files
echo "Injecting debug-ids..."
npx @sentry/cli sourcemaps inject ./dist/frontend

# Upload source maps with debug-ids
echo "Uploading source maps..."
echo "  Organization: $SENTRY_ORG"
echo "  Project: $SENTRY_PROJECT"
echo "  Directory: ./dist/frontend"

# Add release information if version is provided
if [ -n "$APP_VERSION" ]; then
  echo "  Release: $APP_VERSION"
  RELEASE_FLAG="--release $APP_VERSION"
else
  RELEASE_FLAG=""
fi

echo ""

# Try with verbose mode for debugging
if [ "$SENTRY_DEBUG" = "true" ]; then
    npx @sentry/cli sourcemaps upload \
      --org "$SENTRY_ORG" \
      --project "$SENTRY_PROJECT" \
      $RELEASE_FLAG \
      --verbose \
      ./dist/frontend
else
    npx @sentry/cli sourcemaps upload \
      --org "$SENTRY_ORG" \
      --project "$SENTRY_PROJECT" \
      $RELEASE_FLAG \
      ./dist/frontend
fi

echo "✅ Source maps with debug-ids uploaded successfully!"

if [ -n "$APP_VERSION" ]; then
  echo "✅ Release $APP_VERSION created with source maps!"
fi

# Optional: Delete source maps from dist to avoid exposing them
if [ "$DELETE_SOURCEMAPS" = "true" ]; then
  echo "🗑️  Deleting source maps from dist..."
  find ./dist/frontend -name "*.map" -type f -delete
  echo "✅ Source maps deleted from dist"
fi