#!/bin/bash

# Development build script - builds without uploading source maps
# Used by start-dev.sh for local development

echo "🔨 Building frontend for development..."
echo "📝 Note: Source maps will NOT be uploaded to Sentry in dev mode"

# Build in development mode
npm run build:dev

echo "✅ Development build complete!"
echo "💡 To test source map upload, use: npm run build:prod"