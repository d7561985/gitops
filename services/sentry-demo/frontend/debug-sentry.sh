#!/bin/bash

# Debug script for Sentry configuration

echo "🔍 Debugging Sentry configuration..."
echo ""

# Load environment variables
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

echo "📋 Current configuration:"
echo "   SENTRY_ORG: ${SENTRY_ORG}"
echo "   SENTRY_PROJECT: ${SENTRY_PROJECT}"
echo "   SENTRY_AUTH_TOKEN: ${SENTRY_AUTH_TOKEN:0:10}..." # Show only first 10 chars
echo ""

# Test with curl first
echo "🔐 Testing API access with curl..."
echo ""

# Test auth token
echo "Testing auth token..."
RESPONSE=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" \
    "https://sentry.io/api/0/")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ Auth token is valid"
else
    echo "❌ Auth token invalid or expired (HTTP $HTTP_CODE)"
    echo "Response: $(echo "$RESPONSE" | head -n-1)"
fi

echo ""
echo "📂 Testing organization access..."
RESPONSE=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" \
    "https://sentry.io/api/0/organizations/${SENTRY_ORG}/")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ Organization '${SENTRY_ORG}' accessible"
else
    echo "❌ Cannot access organization '${SENTRY_ORG}' (HTTP $HTTP_CODE)"
    echo "Response: $(echo "$RESPONSE" | head -n-1 | jq -r '.detail // .' 2>/dev/null || echo "$RESPONSE")"
fi

echo ""
echo "📁 Testing project access..."
RESPONSE=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" \
    "https://sentry.io/api/0/projects/${SENTRY_ORG}/${SENTRY_PROJECT}/")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ Project '${SENTRY_PROJECT}' in org '${SENTRY_ORG}' accessible"
    echo "Project info:"
    echo "$RESPONSE" | head -n-1 | jq -r '{name: .name, slug: .slug, platform: .platform}' 2>/dev/null || echo "Cannot parse project info"
else
    echo "❌ Cannot access project '${SENTRY_PROJECT}' in org '${SENTRY_ORG}' (HTTP $HTTP_CODE)"
    echo "Response: $(echo "$RESPONSE" | head -n-1 | jq -r '.detail // .' 2>/dev/null || echo "$RESPONSE")"
fi

echo ""
echo "🔍 Listing available organizations..."
RESPONSE=$(curl -s -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" "https://sentry.io/api/0/organizations/")
echo "$RESPONSE" | jq -r '.[] | "- \(.slug) (\(.name))"' 2>/dev/null || echo "Cannot parse organizations"

echo ""
echo "📋 Using Sentry CLI..."
npx @sentry/cli --version

echo ""
echo "💡 Tips:"
echo "   - Make sure SENTRY_ORG matches your organization slug (not display name)"
echo "   - Make sure SENTRY_PROJECT matches your project slug (not display name)"
echo "   - The project slug is in the URL: sentry.io/organizations/ORG/projects/PROJECT/"
echo "   - Auth token needs 'project:write' scope for source map upload"