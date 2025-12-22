#!/bin/bash

# Alternative source map upload using Sentry API directly

# Load environment variables
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

echo "📦 Uploading source maps using Sentry API..."
echo ""

# Check required vars
if [ -z "$SENTRY_AUTH_TOKEN" ] || [ -z "$SENTRY_ORG" ] || [ -z "$SENTRY_PROJECT" ]; then
    echo "❌ Missing required environment variables"
    exit 1
fi

# Get Sentry base URL (for self-hosted instances)
SENTRY_URL=${SENTRY_URL:-"https://sentry.io"}

# First, let's check if we can access the project
echo "🔍 Checking project access..."
RESPONSE=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" \
    "$SENTRY_URL/api/0/projects/$SENTRY_ORG/$SENTRY_PROJECT/")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | head -n-1)

if [ "$HTTP_CODE" != "200" ]; then
    echo "❌ Cannot access project. HTTP Status: $HTTP_CODE"
    echo "Response: $BODY"
    echo ""
    echo "💡 Common issues:"
    echo "   - Wrong organization slug (check URL: sentry.io/organizations/YOUR-ORG/)"
    echo "   - Wrong project slug (check project settings)"
    echo "   - Token doesn't have access to this organization/project"
    exit 1
fi

echo "✅ Project access confirmed"
echo ""

# Now try the CLI again with more specific error handling
echo "📤 Uploading with CLI..."
npx @sentry/cli sourcemaps upload \
    --org "$SENTRY_ORG" \
    --project "$SENTRY_PROJECT" \
    --auth-token "$SENTRY_AUTH_TOKEN" \
    ./dist/frontend/browser 2>&1 | tee upload.log

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo ""
    echo "❌ Upload failed. Check upload.log for details"
    echo ""
    echo "💡 Try running with debug mode:"
    echo "   SENTRY_DEBUG=true ./upload-sourcemaps.sh"
else
    echo ""
    echo "✅ Source maps uploaded successfully!"
fi