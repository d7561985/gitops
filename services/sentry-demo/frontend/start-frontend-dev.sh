#!/bin/bash

# Development start script for Angular frontend
# This script is used by start-dev.sh for development mode

echo "🚀 Starting Angular frontend in development mode..."

# Check if node_modules exists
if [ ! -d "node_modules" ]; then
    echo "📦 Installing dependencies..."
    npm install
fi

# Build development version without source map upload
echo "🔨 Building development version..."
./build-dev.sh

# Start the development server
echo "🌐 Starting development server on http://localhost:4200"
npm start