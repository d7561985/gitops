#!/bin/bash

# Direct source map upload without org validation
# For tokens without org:read permission

# Load environment variables
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

echo "📦 Direct source map upload (without org validation)..."
echo ""

# Check required vars
if [ -z "$SENTRY_AUTH_TOKEN" ]; then
    echo "❌ Error: SENTRY_AUTH_TOKEN not set"
    exit 1
fi

# Inject debug-ids first
echo "1️⃣ Injecting debug-ids..."
npx @sentry/cli sourcemaps inject ./dist/frontend/browser

# Upload with minimal permissions
echo ""
echo "2️⃣ Uploading source maps..."
echo "   Organization: $SENTRY_ORG"
echo "   Project: $SENTRY_PROJECT"
echo ""

# Use --no-rewrite flag to skip some validations
npx @sentry/cli sourcemaps upload \
    --auth-token "$SENTRY_AUTH_TOKEN" \
    --org "$SENTRY_ORG" \
    --project "$SENTRY_PROJECT" \
    --no-rewrite \
    ./dist/frontend/browser 2>&1

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo ""
    echo "✅ Source maps uploaded successfully!"
else
    echo ""
    echo "❌ Upload failed with exit code: $EXIT_CODE"
    echo ""
    echo "💡 If you see 403 errors, your token needs these permissions:"
    echo "   - org:read (to access organization)"
    echo "   - project:write (to upload source maps)"
    echo ""
    echo "   Go to: https://sentry.io/settings/account/api/auth-tokens/"
    echo "   Edit your token and add these scopes"
fi

# Optional: Delete source maps
if [ "$DELETE_SOURCEMAPS" = "true" ]; then
    echo ""
    echo "🗑️  Deleting source maps from dist..."
    find ./dist/frontend/browser -name "*.map" -type f -delete
    echo "✅ Source maps deleted"
fi