#!/bin/bash

# Simple test script to verify Sentry access

# Load environment variables
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

echo "🔍 Testing Sentry Access"
echo "========================"
echo ""

# Check if we have the required env vars
if [ -z "$SENTRY_AUTH_TOKEN" ]; then
    echo "❌ SENTRY_AUTH_TOKEN not set"
    exit 1
fi

echo "1️⃣ Testing basic API access..."
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" \
    -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" \
    "https://sentry.io/api/0/"

echo ""
echo "2️⃣ Getting your user info..."
USER_INFO=$(curl -s -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" "https://sentry.io/api/0/users/me/")
echo "User: $(echo "$USER_INFO" | jq -r '.email // "Unknown"' 2>/dev/null)"

echo ""
echo "3️⃣ Listing all accessible organizations..."
ORGS=$(curl -s -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" "https://sentry.io/api/0/organizations/")
echo "$ORGS" | jq -r '.[] | "   - \(.slug) [\(.name)]"' 2>/dev/null || echo "   Error parsing organizations"

echo ""
echo "4️⃣ For organization '$SENTRY_ORG', listing projects..."
PROJECTS=$(curl -s -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" "https://sentry.io/api/0/organizations/$SENTRY_ORG/projects/")
if echo "$PROJECTS" | jq -e '.detail' >/dev/null 2>&1; then
    echo "   ❌ Error: $(echo "$PROJECTS" | jq -r '.detail')"
else
    echo "$PROJECTS" | jq -r '.[] | "   - \(.slug) [\(.name)] - Platform: \(.platform)"' 2>/dev/null || echo "   Error parsing projects"
fi

echo ""
echo "5️⃣ Testing sourcemap upload endpoint..."
TEST_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
    -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" \
    -X POST \
    "https://sentry.io/api/0/projects/$SENTRY_ORG/$SENTRY_PROJECT/files/source-maps/" \
    -F "name=test.js" \
    -F "file=@/dev/null" 2>/dev/null || echo "CURL_ERROR")

if [[ "$TEST_RESPONSE" == *"HTTP_CODE:403"* ]]; then
    echo "   ❌ No permission to upload source maps"
    echo "   Check: Token has 'project:write' scope?"
elif [[ "$TEST_RESPONSE" == *"HTTP_CODE:404"* ]]; then
    echo "   ❌ Project not found: $SENTRY_ORG/$SENTRY_PROJECT"
elif [[ "$TEST_RESPONSE" == *"HTTP_CODE:400"* ]] || [[ "$TEST_RESPONSE" == *"HTTP_CODE:422"* ]]; then
    echo "   ✅ Endpoint accessible (test upload rejected as expected)"
else
    echo "   ⚠️  Unexpected response"
fi

echo ""
echo "💡 Summary:"
echo "   - Your token belongs to: $(echo "$USER_INFO" | jq -r '.email // "Unknown"' 2>/dev/null)"
echo "   - You have access to $(echo "$ORGS" | jq -r 'length' 2>/dev/null || echo "?") organization(s)"
echo "   - Current config: $SENTRY_ORG/$SENTRY_PROJECT"